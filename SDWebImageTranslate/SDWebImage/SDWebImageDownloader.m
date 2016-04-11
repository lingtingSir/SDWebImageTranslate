/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloader.h"
#import "SDWebImageDownloaderOperation.h"
#import <ImageIO/ImageIO.h>

// 开始下载
NSString *const SDWebImageDownloadStartNotification = @"SDWebImageDownloadStartNotification";

/// 停止下载
NSString *const SDWebImageDownloadStopNotification = @"SDWebImageDownloadStopNotification";

/**
 *  / const *    *const 区别
 *    const * 解释： kProressCallbackKey为常量，不可以改变值，可以改变指向例如kProressCallbackKey = @"proerasdas";这是错误的，   *kProressCallbackKey = &i;这是正确的
 */
static NSString *const kProgressCallbackKey = @"progress";
static NSString *const kCompletedCallbackKey = @"completed";

@interface SDWebImageDownloader ()

// 下载操作队列
@property (strong, nonatomic) NSOperationQueue *downloadQueue;
// 最后添加的操作 先进后出顺序顺序
@property (weak, nonatomic) NSOperation *lastAddedOperation;
// 图片下载类
@property (assign, nonatomic) Class operationClass;
// URL回调字典 以URL为key，你装有URL下载的进度block和完成block的数组为value
@property (strong, nonatomic) NSMutableDictionary *URLCallbacks;
// HTTP请求头
@property (strong, nonatomic) NSMutableDictionary *HTTPHeaders;
// This queue is used to serialize the handling of the network responses of all the download operation in a single queue
// barrierQueue是一个并行队列，在一个单一队列中顺序处理所有下载操作的网络响应
@property (SDDispatchQueueSetterSementics, nonatomic) dispatch_queue_t barrierQueue;

@end

@implementation SDWebImageDownloader

+ (void)initialize {
    // Bind SDNetworkActivityIndicator if available (download it here: http://github.com/rs/SDNetworkActivityIndicator )
    // To use it, just add #import "SDNetworkActivityIndicator.h" in addition to the SDWebImage import
    if (NSClassFromString(@"SDNetworkActivityIndicator")) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id activityIndicator = [NSClassFromString(@"SDNetworkActivityIndicator") performSelector:NSSelectorFromString(@"sharedActivityIndicator")];
#pragma clang diagnostic pop
        
        // Remove observer in case it was previously added.
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStopNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"startActivity")
                                                     name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"stopActivity")
                                                     name:SDWebImageDownloadStopNotification object:nil];
    }
}

+ (SDWebImageDownloader *)sharedDownloader {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (id)init {
    if ((self = [super init])) {
        _operationClass = [SDWebImageDownloaderOperation class];
        _executionOrder = SDWebImageDownloaderFIFOExecutionOrder;
        _downloadQueue = [NSOperationQueue new];
        _downloadQueue.maxConcurrentOperationCount = 6;
        _URLCallbacks = [NSMutableDictionary new];
        _HTTPHeaders = [NSMutableDictionary dictionaryWithObject:@"image/webp,image/*;q=0.8" forKey:@"Accept"];
        /* 并行的处理所有下载操作的网络响应
         第一个参数：队列名称
         第二个参数：队列类型，NULL 则创建串行队列处理方式,DISPATCH_QUEUE_CONCURRENT则是并行队列处理方式
         */
        /**
         * @const DISPATCH_QUEUE_CONCURRENT
         * @discussion可能并发和支持调用块A发送队列
         * 与调度屏障API提交障碍块。
         */
        _barrierQueue = dispatch_queue_create("com.hackemist.SDWebImageDownloaderBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
        _downloadTimeout = 15.0;
    }
    return self;
}

- (void)dealloc {
    [self.downloadQueue cancelAllOperations];
    SDDispatchQueueRelease(_barrierQueue);
}

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (value) {
        self.HTTPHeaders[field] = value;
    }
    else {
        [self.HTTPHeaders removeObjectForKey:field];
    }
}

- (NSString *)valueForHTTPHeaderField:(NSString *)field {
    return self.HTTPHeaders[field];
}

- (void)setMaxConcurrentDownloads:(NSInteger)maxConcurrentDownloads {
    _downloadQueue.maxConcurrentOperationCount = maxConcurrentDownloads;
}

- (NSUInteger)currentDownloadCount {
    return _downloadQueue.operationCount;
}

- (NSInteger)maxConcurrentDownloads {
    return _downloadQueue.maxConcurrentOperationCount;
}

- (void)setOperationClass:(Class)operationClass {
    _operationClass = operationClass ?: [SDWebImageDownloaderOperation class];
}

- (id <SDWebImageOperation>)downloadImageWithURL:(NSURL *)url options:(SDWebImageDownloaderOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageDownloaderCompletedBlock)completedBlock {
    // 下载对象  block中要修改的变量需要__block修饰
    __block SDWebImageDownloaderOperation *operation;
    // weak self  防止retain cycle
    __weak SDWebImageDownloader *wself = self;  // 下面几张代码中 有使用SDWebImageDownloader对象赋值给SDWebImageDownloader 对象，设置弱引用防止循环引用，
    // 添加设置回调  调用另一方法,在创建回调的block中创建新的操作，配置之后将其放入downloadQueue操作队列中。
    [self addProgressCallback:progressBlock andCompletedBlock:completedBlock forURL:url createCallback:^{
        // 设置延时时长 为 15.0秒
        NSTimeInterval timeoutInterval = wself.downloadTimeout;
        if (timeoutInterval == 0.0) {
            timeoutInterval = 15.0;
        }

        // In order to prevent from potential duplicate caching (NSURLCache + SDImageCache) we disable the cache for image requests if told otherwise
        // 为防止重复缓存(NSURLCache + SDImageCache)，如果设置了 SDWebImageDownloaderUseNSURLCache（系统自带的使用 NSURLCache 和默认缓存策略），则禁用 SDImageCache
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:(options & SDWebImageDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData) timeoutInterval:timeoutInterval];
        // 是否处理cookies
        request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies);
        request.HTTPShouldUsePipelining = YES;
        if (wself.headersFilter) {
            request.allHTTPHeaderFields = wself.headersFilter(url, [wself.HTTPHeaders copy]);
        }
        else {
            request.allHTTPHeaderFields = wself.HTTPHeaders;
        }
        // 创建下载对象 在这里是 SDWebImageDownloaderOperation 类
        operation = [[wself.operationClass alloc] initWithRequest:request
                                                          options:options
                                                         progress:^(NSInteger receivedSize, NSInteger expectedSize) {
                                                             SDWebImageDownloader *sself = wself;
                                                             if (!sself) return;
                                                             // URL回调数组
                                                             NSArray *callbacksForURL = [sself callbacksForURL:url];
                                                             for (NSDictionary *callbacks in callbacksForURL) {
                                                                 SDWebImageDownloaderProgressBlock callback = callbacks[kProgressCallbackKey];
                                                                 if (callback) callback(receivedSize, expectedSize);
                                                             }
                                                         }
                                                        completed:^(UIImage *image, NSData *data, NSError *error, BOOL finished) {
                                                            SDWebImageDownloader *sself = wself;
                                                            if (!sself) return;
                                                            NSArray *callbacksForURL = [sself callbacksForURL:url];
                                                            if (finished) {
                                                                [sself removeCallbacksForURL:url];
                                                            }
                                                            for (NSDictionary *callbacks in callbacksForURL) {
                                                               
                                                                SDWebImageDownloaderCompletedBlock callback = callbacks[kCompletedCallbackKey];
                                                                if (callback) callback(image, data, error, finished);
                                                            }
                                                        }
                                                        cancelled:^{
                                                            SDWebImageDownloader *sself = wself;
                                                            if (!sself) return;
                                                            // 如果下载完成 则从回调数组里面删除
                                                            [sself removeCallbacksForURL:url];
                                                        }];
        
        // 如果设置了用户名 & 口令
        if (wself.username && wself.password) {
            // 设置 https 访问时身份验证使用的凭据
            operation.credential = [NSURLCredential credentialWithUser:wself.username password:wself.password persistence:NSURLCredentialPersistenceForSession];
        }
        // 设置队列的优先级
        if (options & SDWebImageDownloaderHighPriority) {
            operation.queuePriority = NSOperationQueuePriorityHigh;
        } else if (options & SDWebImageDownloaderLowPriority) {
            operation.queuePriority = NSOperationQueuePriorityLow;
        }
        // 将下载操作添加到下载队列中
        [wself.downloadQueue addOperation:operation];
        // 如果是后进先出操作顺序 则将该操作置为最后一个操作
        if (wself.executionOrder == SDWebImageDownloaderLIFOExecutionOrder) {
            // Emulate LIFO execution order by systematically adding new operations as last operation's dependency
            [wself.lastAddedOperation addDependency:operation];
            wself.lastAddedOperation = operation;
        }
    }];

    return operation;
}


/**
 *  添加设置回调
 *
 *  @param progressBlock  下载进度block
 *  @param completedBlock 下载完成block
 *  @param url            下载URL
 *  @param createCallback 创建回调block
 */
- (void)addProgressCallback:(SDWebImageDownloaderProgressBlock)progressBlock andCompletedBlock:(SDWebImageDownloaderCompletedBlock)completedBlock forURL:(NSURL *)url createCallback:(SDWebImageNoParamsBlock)createCallback {
    // The URL will be used as the key to the callbacks dictionary so it cannot be nil. If it is nil immediately call the completed block with no image or data.
    // URL不能为空
    if (url == nil) {
        if (completedBlock != nil) {
            completedBlock(nil, nil, nil, NO);
        }
        return;
    }
    // dispatch_barrier_sync 保证同一时间只有一个线程操作 URLCallbacks
    dispatch_barrier_sync(self.barrierQueue, ^{
        // 是否第一次操作
        BOOL first = NO;
        if (!self.URLCallbacks[url]) {
            self.URLCallbacks[url] = [NSMutableArray new];
            first = YES;
        }

        // Handle single download of simultaneous download request for the same URL
        // 处理 同一个URL的单个下载
        NSMutableArray *callbacksForURL = self.URLCallbacks[url];
        NSMutableDictionary *callbacks = [NSMutableDictionary new];
        // 将 进度block和完成block赋值
        if (progressBlock) callbacks[kProgressCallbackKey] = [progressBlock copy];
        if (completedBlock) callbacks[kCompletedCallbackKey] = [completedBlock copy];
        [callbacksForURL addObject:callbacks];
        // 已URL为key进行赋值
        self.URLCallbacks[url] = callbacksForURL;
        
        // 如果是第一次下载 则回调
        if (first) {
            // 通过这个回调，可以实时获取下载进度以及是下载完成情况
            createCallback();
        }
    });
}

- (NSArray *)callbacksForURL:(NSURL *)url {
    __block NSArray *callbacksForURL;
    // dispatch_sync 也是将block发送到指定的线程去执行，但是当前的线程会阻塞，等待block在指定线程执行完成后才会继续向下执行。 dispatch_async 是将block发送到指定线程去执行，当前线程不会等待，会继续向下执行。 self.barrierQueue队列类型为并行队列,设置一个线程同步，使用并行队列的执行方式获取回调URL
    dispatch_sync(self.barrierQueue, ^{
        callbacksForURL = self.URLCallbacks[url];
    });
    return [callbacksForURL copy];
}

- (void)removeCallbacksForURL:(NSURL *)url {
    // 使用此方法创建的任务首先会查看队列中有没有别的任务要执行，如果有，则会等待已有任务执行完毕再执行；同时在此方法后添加的任务必须等待此方法中任务执行后才能执行。（利用这个方法可以控制执行顺序，例如前面先加载最后一张图片的需求就可以先使用这个方法将最后一张图片加载的操作添加到队列，然后调用dispatch_async()添加其他图片加载任务）
    dispatch_barrier_async(self.barrierQueue, ^{
        [self.URLCallbacks removeObjectForKey:url];
    });
}

- (void)setSuspended:(BOOL)suspended {
    [self.downloadQueue setSuspended:suspended];
}

@end
