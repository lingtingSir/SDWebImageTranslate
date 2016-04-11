/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageManager.h"
#import <objc/message.h>

@interface SDWebImageCombinedOperation : NSObject <SDWebImageOperation>

@property (assign, nonatomic, getter = isCancelled) BOOL cancelled;
@property (copy, nonatomic) SDWebImageNoParamsBlock cancelBlock;
@property (strong, nonatomic) NSOperation *cacheOperation;

@end

@interface SDWebImageManager ()

// 缓存对象
@property (strong, nonatomic, readwrite) SDImageCache *imageCache;
// 下载对象
@property (strong, nonatomic, readwrite) SDWebImageDownloader *imageDownloader;
// 失败的URL集合
@property (strong, nonatomic) NSMutableArray *failedURLs;
// 操作线程数组
@property (strong, nonatomic) NSMutableArray *runningOperations;

@end

@implementation SDWebImageManager

+ (id)sharedManager {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (id)init {
    if ((self = [super init])) {
        _imageCache = [self createCache];
        _imageDownloader = [SDWebImageDownloader sharedDownloader];
        _failedURLs = [NSMutableArray new];
        _runningOperations = [NSMutableArray new];
    }
    return self;
}

- (SDImageCache *)createCache {
    return [SDImageCache sharedImageCache];
}

- (NSString *)cacheKeyForURL:(NSURL *)url {
    if (self.cacheKeyFilter) {
        return self.cacheKeyFilter(url);
    }
    else {
        return [url absoluteString];
    }
}

- (BOOL)cachedImageExistsForURL:(NSURL *)url {
    NSString *key = [self cacheKeyForURL:url];
    if ([self.imageCache imageFromMemoryCacheForKey:key] != nil) return YES;
    return [self.imageCache diskImageExistsWithKey:key];
}

- (BOOL)diskImageExistsForURL:(NSURL *)url {
    NSString *key = [self cacheKeyForURL:url];
    return [self.imageCache diskImageExistsWithKey:key];
}

- (void)cachedImageExistsForURL:(NSURL *)url
                     completion:(SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    BOOL isInMemoryCache = ([self.imageCache imageFromMemoryCacheForKey:key] != nil);
    
    if (isInMemoryCache) {
        // making sure we call the completion block on the main queue
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock(YES);
            }
        });
        return;
    }
    
    [self.imageCache diskImageExistsWithKey:key completion:^(BOOL isInDiskCache) {
        // the completion block of checkDiskCacheForImageWithKey:completion: is always called on the main queue, no need to further dispatch
        if (completionBlock) {
            completionBlock(isInDiskCache);
        }
    }];
}

- (void)diskImageExistsForURL:(NSURL *)url
                   completion:(SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    [self.imageCache diskImageExistsWithKey:key completion:^(BOOL isInDiskCache) {
        // the completion block of checkDiskCacheForImageWithKey:completion: is always called on the main queue, no need to further dispatch
        if (completionBlock) {
            completionBlock(isInDiskCache);
        }
    }];
}


/*
 1. id foo1;
 （什么是 id？
 id 在 objc.h 中定义如下:
 
 /// A pointer to an instance of a class. （id 是指向一个 objc_object 结构体的指针。）
 typedef struct objc_object *id;
 id 这个struct的定义本身就带了一个 *, 所以我们在使用其他NSObject类型的实例时需要在前面加上 *， 而使用 id 时却不用。
 objc_object 在 objc.h 中定义如下:
 
 /// Represents an instance of a class.
 struct objc_object {
 Class isa;
 }; 
 
 这个时候我们知道Objective-C中的object在最后会被转换成C的结构体，而在这个struct中有一个 isa 指针，指向它的类别 Class。
 
 那么什么是Class呢
 
 在 objc.h 中定义如下:
 
 /// An opaque type that represents an Objective-C class.
 typedef struct objc_class *Class; （Class本身指向的也是一个C的struct objc_class。）
 
 那么什么是Class呢
 objc_class定义如下:
 
 struct objc_class {
 Class isa  OBJC_ISA_AVAILABILITY;
 #if !__OBJC2__
 Class super_class                                        OBJC2_UNAVAILABLE;
 const char *name                                         OBJC2_UNAVAILABLE;
 long version                                             OBJC2_UNAVAILABLE;
 long info                                                OBJC2_UNAVAILABLE;
 long instance_size                                       OBJC2_UNAVAILABLE;
 struct objc_ivar_list *ivars                             OBJC2_UNAVAILABLE;
 struct objc_method_list **methodLists                    OBJC2_UNAVAILABLE;
 struct objc_cache *cache                                 OBJC2_UNAVAILABLE;
 struct objc_protocol_list *protocols                     OBJC2_UNAVAILABLE;
 #endif
 } OBJC2_UNAVAILABLE;
 该结构体中，isa 指向所属Class， super_class指向父类别。
 我们看到在Objective-C的设计哲学中，一切都是对象。Class在设计中本身也是一个对象。而这个Class对象的对应的类，我们叫它 Meta Class。即Class结构体中的 isa 指向的就是它的 Meta Class。
 
 根据上面的描述，我们可以把Meta Class理解为 一个Class对象的Class。简单的说：
 
 当我们发送一个消息给一个NSObject对象时，这条消息会在对象的类的方法列表里查找
 当我们发送一个消息给一个类时，这条消息会在类的Meta Class的方法列表里查找
 而 Meta Class本身也是一个Class，它跟其他Class一样也有自己的 isa 和 super_class 指针。看
 
 每个Class都有一个isa指针指向一个唯一的Meta Class
 每一个Meta Class的isa指针都指向最上层的Meta Class（图中的NSObject的Meta Class）
 最上层的Meta Class的isa指针指向自己，形成一个回路
 每一个Meta Class的super class指针指向它原本Class的 Super Class的Meta Class。但是最上层的Meta Class的 Super Class指向NSObject Class本身
 最上层的NSObject Class的super class指向 nil

 ）
 
 2. NSObject *foo2;
 3. id<NSObject> foo3;
 第一种是最常用，它简单地申明了指向对象的指针，没有给编译器任何类型信息，因此，编译器不会做类型检查。但也因为是这样，你可以发送任何信息给id类型的对象。这就是为什么+alloc返回id类型，但调用[[Foo alloc] init]不会产生编译错误。
 
 因此，id类型是运行时的动态类型，编译器无法知道它的真实类型，即使你发送一个id类型没有的方法，也不会产生编译警告。
 
 我们知道，id类型是一个Objective-C对象，但并不是都指向继承自NSOjbect的对象，即使这个类型和NSObject对象有很多共同的方法，像retain和release。要让编译器知道这个类继承自NSObject，一种解决办法就是像第2种那样，使用NSObject静态类型，当你发送NSObject没有的方法，像length或者count时，编译器就会给出警告。这也意味着，你可以安全地使用像retain，release，description这些方法。
 
 因此，申明一个通用的NSObject对象指针和你在其它语言里做的类似，像java，但其它语言有一定的限制，没有像Objective-C这样灵活。并不是所有的Foundation/Cocoa对象都继承息NSObject，比如NSProxy就不从NSObject继承，所以你无法使用NSObject＊指向这个对象，即使NSProxy对象有release和retain这样的通用方法。为了解决这个问题，这时候，你就需要一个指向拥有NSObject方法对象的指针，这就是第3种申明的使用情景。
 
 id<NSObject>告诉编译器，你不关心对象是什么类型，但它必须遵守NSObject协议(protocol)，编译器就能保证所有赋值给id<NSObject>类型的对象都遵守NSObject协议(protocol)。这样的指针可以指向任何NSObject对象，因为NSObject对象遵守NSObject协议(protocol)，而且，它也可以用来保存NSProxy对象，因为它也遵守NSObject协议(protocol)。这是非常强大，方便且灵活，你不用关心对象是什么类型，而只关心它实现了哪些方法。
 
 */
- (id <SDWebImageOperation>)downloadImageWithURL:(NSURL *)url
                                         options:(SDWebImageOptions)options
                                        progress:(SDWebImageDownloaderProgressBlock)progressBlock
                                       completed:(SDWebImageCompletionWithFinishedBlock)completedBlock {
    // Invoking this method without a completedBlock is pointless
    NSAssert(completedBlock != nil, @"If you mean to prefetch the image, use -[SDWebImagePrefetcher prefetchURLs] instead");

    // Very common mistake is to send the URL using NSString object instead of NSURL. For some strange reason, XCode won't
    // throw any warning for this type mismatch. Here we failsafe this error by allowing URLs to be passed as NSString.
    // 一个非常普通的错误就是把NSString对象当做NSURL来使用，但是Xcode却不能提示这种类型的错误。所以这里做一下处理
    if ([url isKindOfClass:NSString.class]) {
        url = [NSURL URLWithString:(NSString *)url];
    }

    // Prevents app crashing on argument type error like sending NSNull instead of NSURL
    // 防止URL为空时 程序崩溃
    if (![url isKindOfClass:NSURL.class]) {
        url = nil;
    }
    // 创建对象 并弱引用
    __block SDWebImageCombinedOperation *operation = [SDWebImageCombinedOperation new];
    __weak SDWebImageCombinedOperation *weakOperation = operation;
    // 是否是失败的URL
    BOOL isFailedUrl = NO;
    @synchronized (self.failedURLs) {
        // 检查黑名单
        isFailedUrl = [self.failedURLs containsObject:url];
    }

    if (!url || (!(options & SDWebImageRetryFailed) && isFailedUrl)) {
        dispatch_main_sync_safe(^{
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil];
            completedBlock(nil, error, SDImageCacheTypeNone, YES, url);
        });
        return operation;
    }
    // 将该操作线程添加到数组里面
    @synchronized (self.runningOperations) {
        [self.runningOperations addObject:operation];
    }
    // 根据URL获取缓存的key
    NSString *key = [self cacheKeyForURL:url];
    // 根据key从缓存里面找
    operation.cacheOperation = [self.imageCache queryDiskCacheForKey:key done:^(UIImage *image, SDImageCacheType cacheType) {
        // 如果线程被取消 则删除该操作
        if (operation.isCancelled) {
            @synchronized (self.runningOperations) {
                [self.runningOperations removeObject:operation];
            }

            return;
        }
        // 没有图片 或者 操作类型会刷新缓存 并且 delegate允许下载图片
        if ((!image || options & SDWebImageRefreshCached) && (![self.delegate respondsToSelector:@selector(imageManager:shouldDownloadImageForURL:)] || [self.delegate imageManager:self shouldDownloadImageForURL:url])) {
            // 有图片 并且操作类型为 SDWebImageRefreshCached （先用缓存图片回调block 图片下载完成后再回调block）
            if (image && options & SDWebImageRefreshCached) {
                dispatch_main_sync_safe(^{
                    // If image was found in the cache bug SDWebImageRefreshCached is provided, notify about the cached image
                    // AND try to re-download it in order to let a chance to NSURLCache to refresh it from server.
                    completedBlock(image, nil, cacheType, YES, url);
                });
            }

            // download if no image or requested to refresh anyway, and download allowed by delegate
            // 根据SDWebImageOptions的类型 得到SDWebImageDownloaderOptions 都是一些位运算
            SDWebImageDownloaderOptions downloaderOptions = 0;
            
            if (options & SDWebImageLowPriority) downloaderOptions |= SDWebImageDownloaderLowPriority;
            if (options & SDWebImageProgressiveDownload) downloaderOptions |= SDWebImageDownloaderProgressiveDownload;
            //  组合使用
            if (options & SDWebImageRefreshCached) downloaderOptions |= SDWebImageDownloaderUseNSURLCache;
            if (options & SDWebImageContinueInBackground) downloaderOptions |= SDWebImageDownloaderContinueInBackground;
            if (options & SDWebImageHandleCookies) downloaderOptions |= SDWebImageDownloaderHandleCookies;
            if (options & SDWebImageAllowInvalidSSLCertificates) downloaderOptions |= SDWebImageDownloaderAllowInvalidSSLCertificates;
            if (options & SDWebImageHighPriority) downloaderOptions |= SDWebImageDownloaderHighPriority;
            if (image && options & SDWebImageRefreshCached) {
                // force progressive off if image already cached but forced refreshing
                downloaderOptions &= ~SDWebImageDownloaderProgressiveDownload;
                // ignore image read from NSURLCache if image if cached but force refreshing
                downloaderOptions |= SDWebImageDownloaderIgnoreCachedResponse;
            }
            // 下载图片
            id <SDWebImageOperation> subOperation = [self.imageDownloader downloadImageWithURL:url options:downloaderOptions progress:progressBlock completed:^(UIImage *downloadedImage, NSData *data, NSError *error, BOOL finished) {
                // 操作被取消 则不做任何操作
                if (weakOperation.isCancelled) {
                    // Do nothing if the operation was cancelled
                    // See #699 for more details
                    // if we would call the completedBlock, there could be a race condition between this block and another completedBlock for the same object, so if this one is called second, we will overwrite the new data
                }
                // 出错
                else if (error) {
                    dispatch_main_sync_safe(^{
                        if (!weakOperation.isCancelled) {
                            completedBlock(nil, error, SDImageCacheTypeNone, finished, url);
                        }
                    });
                    // 出错编码：1。链接出错 2.操作被取消 3.下载超时出错
                    if (error.code != NSURLErrorNotConnectedToInternet && error.code != NSURLErrorCancelled && error.code != NSURLErrorTimedOut) {
                        @synchronized (self.failedURLs) { // 添加到失败URL数组
                            if (![self.failedURLs containsObject:url]) {
                                [self.failedURLs addObject:url];
                            }
                        }
                    }
                }
                else { // 下载成功
                    // 是否存储在磁盘，如果是存储在内存当中则得到0
                    BOOL cacheOnDisk = !(options & SDWebImageCacheMemoryOnly);

                    if (options & SDWebImageRefreshCached && image && !downloadedImage) {
                        // Image refresh hit the NSURLCache cache, do not call the completion block
                    }
                    // 图片下载成功 并且需要转换图片，并且不是动画图片（多张）
                    else if (downloadedImage && (!downloadedImage.images || (options & SDWebImageTransformAnimatedImage)) && [self.delegate respondsToSelector:@selector(imageManager:transformDownloadedImage:withURL:)]) {
                        // 在全局队列中 异步进行操作
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                            // 根据代理获取转换后的图片
                            UIImage *transformedImage = [self.delegate imageManager:self transformDownloadedImage:downloadedImage withURL:url];
                            // 转换图片存在 并且下载图片操作已完成 则存储图片
                            if (transformedImage && finished) {
                                BOOL imageWasTransformed = ![transformedImage isEqual:downloadedImage];
                                [self.imageCache storeImage:transformedImage recalculateFromImage:imageWasTransformed imageData:data forKey:key toDisk:cacheOnDisk];
                            }

                            dispatch_main_sync_safe(^{
                                if (!weakOperation.isCancelled) { // block回调
                                    completedBlock(transformedImage, nil, SDImageCacheTypeNone, finished, url);
                                }
                            });
                        });
                    }
                    else { // gif动画图片，存储图片 并且 block回调
                        if (downloadedImage && finished) {
                            [self.imageCache storeImage:downloadedImage recalculateFromImage:NO imageData:data forKey:key toDisk:cacheOnDisk];
                        }

                        dispatch_main_sync_safe(^{
                            if (!weakOperation.isCancelled) {
                                completedBlock(downloadedImage, nil, SDImageCacheTypeNone, finished, url);
                            }
                        });
                    }
                }

                if (finished) {  // 如果已完成 则将该请求操作从数组中删除
                    @synchronized (self.runningOperations) {
                        [self.runningOperations removeObject:operation];
                    }
                }
            }];
            operation.cancelBlock = ^{ // 有图片 并且线程没有被取消 则返回有图片的block
                [subOperation cancel];
                
                @synchronized (self.runningOperations) {
                    [self.runningOperations removeObject:weakOperation];
                }
            };
        }
        else if (image) { // 有图片 并且线程没有被取消 则返回有图片的block
            dispatch_main_sync_safe(^{
                if (!weakOperation.isCancelled) {
                    completedBlock(image, nil, cacheType, YES, url);
                }
            });
            @synchronized (self.runningOperations) {
                [self.runningOperations removeObject:operation];
            }
        }
        else {
            // 图片没有被缓存 并且没有被代理通知可以下载图片 则返回没有图片的block
            // Image not in cache and download disallowed by delegate
            dispatch_main_sync_safe(^{
                if (!weakOperation.isCancelled) {
                    completedBlock(nil, nil, SDImageCacheTypeNone, YES, url);
                }
            });
            @synchronized (self.runningOperations) {
                [self.runningOperations removeObject:operation];
            }
        }
    }];

    return operation;
}

- (void)saveImageToCache:(UIImage *)image forURL:(NSURL *)url {
    if (image && url) {
        NSString *key = [self cacheKeyForURL:url];
        [self.imageCache storeImage:image forKey:key toDisk:YES];
    }
}

- (void)cancelAll {
    @synchronized (self.runningOperations) {
        NSArray *copiedOperations = [self.runningOperations copy];
        [copiedOperations makeObjectsPerformSelector:@selector(cancel)];
        [self.runningOperations removeObjectsInArray:copiedOperations];
    }
}

- (BOOL)isRunning {
    return self.runningOperations.count > 0;
}

@end


@implementation SDWebImageCombinedOperation

- (void)setCancelBlock:(SDWebImageNoParamsBlock)cancelBlock {
    // check if the operation is already cancelled, then we just call the cancelBlock
    if (self.isCancelled) {
        if (cancelBlock) {
            cancelBlock();
        }
        _cancelBlock = nil; // don't forget to nil the cancelBlock, otherwise we will get crashes
    } else {
        _cancelBlock = [cancelBlock copy];
    }
}

- (void)cancel {
    self.cancelled = YES;
    if (self.cacheOperation) {
        [self.cacheOperation cancel];
        self.cacheOperation = nil;
    }
    if (self.cancelBlock) {
        self.cancelBlock();
        
        // TODO: this is a temporary fix to #809.
        // Until we can figure the exact cause of the crash, going with the ivar instead of the setter
//        self.cancelBlock = nil;
        _cancelBlock = nil;
    }
}

@end
