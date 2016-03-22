/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 上传多张图片时的循环代码，
 */

#import "SDWebImagePrefetcher.h"

#if (!defined(DEBUG) && !defined (SD_VERBOSE)) || defined(SD_LOG_NONE)
#define NSLog(...)
#endif

@interface SDWebImagePrefetcher ()

@property (strong, nonatomic) SDWebImageManager *manager;
@property (strong, nonatomic) NSArray *prefetchURLs;
@property (assign, nonatomic) NSUInteger requestedCount;
@property (assign, nonatomic) NSUInteger skippedCount;
@property (assign, nonatomic) NSUInteger finishedCount;
@property (assign, nonatomic) NSTimeInterval startedTime;
@property (copy, nonatomic) SDWebImagePrefetcherCompletionBlock completionBlock;
@property (copy, nonatomic) SDWebImagePrefetcherProgressBlock progressBlock;

@end

@implementation SDWebImagePrefetcher

+ (SDWebImagePrefetcher *)sharedImagePrefetcher {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (id)init {
    if ((self = [super init])) {
        _manager = [SDWebImageManager new];
        _options = SDWebImageLowPriority;
        self.maxConcurrentDownloads = 3;
    }
    return self;
}

- (void)setMaxConcurrentDownloads:(NSUInteger)maxConcurrentDownloads {
    self.manager.imageDownloader.maxConcurrentDownloads = maxConcurrentDownloads;
}

- (NSUInteger)maxConcurrentDownloads {
    return self.manager.imageDownloader.maxConcurrentDownloads;
}

/**
 *  开始预取URL数组的第几张图片
 *
 *  @param index index description
 */
- (void)startPrefetchingAtIndex:(NSUInteger)index {
    // 判断index是否越界
    if (index >= self.prefetchURLs.count) return;
    // 请求个数 +1
    self.requestedCount++;
    // 用SDWebImageManager 下载图片
    [self.manager downloadImageWithURL:self.prefetchURLs[index] options:self.options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        if (!finished) return;
        // 完成个数 +1
        self.finishedCount++;
        // 有图片
        if (image) {
            // 进度block回调
            if (self.progressBlock) {
                self.progressBlock(self.finishedCount,[self.prefetchURLs count]); 
            }
            NSLog(@"Prefetched %@ out of %@", @(self.finishedCount), @(self.prefetchURLs.count));
        }
        else {
            // 进度block回调
            if (self.progressBlock) {
                self.progressBlock(self.finishedCount,[self.prefetchURLs count]);
            }
            NSLog(@"Prefetched %@ out of %@ (Failed)", @(self.finishedCount), @(self.prefetchURLs.count));
            // 下载完成 但是没图片 跳过个数 +1
            // Add last failed
            // Add last failed
            self.skippedCount++;
        }
        // delegate 回调
        if ([self.delegate respondsToSelector:@selector(imagePrefetcher:didPrefetchURL:finishedCount:totalCount:)]) {
            [self.delegate imagePrefetcher:self
                            didPrefetchURL:self.prefetchURLs[index]
                             finishedCount:self.finishedCount
                                totalCount:self.prefetchURLs.count
            ];
        }
        // 如果预存完成个数大于请求的个数，则请求最后一个预存图片
        if (self.prefetchURLs.count > self.requestedCount) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self startPrefetchingAtIndex:self.requestedCount];
            });
        }
        // 如果完成个数与请求个数相等 则下载已完成
        else if (self.finishedCount == self.requestedCount) {
            [self reportStatus];
            if (self.completionBlock) {
                self.completionBlock(self.finishedCount, self.skippedCount);
                self.completionBlock = nil;
            }
        }
    }];
}

/**
 *  报告完成的状态
 */
- (void)reportStatus {
    NSUInteger total = [self.prefetchURLs count];
    // delegate回调
    NSLog(@"Finished prefetching (%@ successful, %@ skipped, timeElasped %.2f)", @(total - self.skippedCount), @(self.skippedCount), CFAbsoluteTimeGetCurrent() - self.startedTime);
    if ([self.delegate respondsToSelector:@selector(imagePrefetcher:didFinishWithTotalCount:skippedCount:)]) {
        [self.delegate imagePrefetcher:self
               didFinishWithTotalCount:(total - self.skippedCount)
                          skippedCount:self.skippedCount
        ];
    }
}
/**
 *  开始预取URL
 *
 *  @param urls URL数组
 */
- (void)prefetchURLs:(NSArray *)urls {
    [self prefetchURLs:urls progress:nil completed:nil];
}
/**
 *  预取URL
 *
 *  @param urls            url数组
 *  @param progressBlock   进度block
 *  @param completionBlock 完成block
 */
- (void)prefetchURLs:(NSArray *)urls progress:(SDWebImagePrefetcherProgressBlock)progressBlock completed:(SDWebImagePrefetcherCompletionBlock)completionBlock {
    // 取消预取 防止重复的操作
    [self cancelPrefetching]; // Prevent duplicate prefetch request
    // 开始时间
    self.startedTime = CFAbsoluteTimeGetCurrent();
    self.prefetchURLs = urls;
    self.completionBlock = completionBlock;
    self.progressBlock = progressBlock;
    // 如果URL为空
    if(urls.count == 0){ 
        if(completionBlock){
            completionBlock(0,0);
        }
    }else{
        // Starts prefetching from the very first image on the list with the max allowed concurrency
        // 用dispatch_apply 优化并发下载的性能
        NSUInteger listCount = self.prefetchURLs.count;
        for (NSUInteger i = 0; i < self.maxConcurrentDownloads && self.requestedCount < listCount; i++) {
            [self startPrefetchingAtIndex:i];
        }
    }
}

- (void)cancelPrefetching {
    self.prefetchURLs = nil;
    self.skippedCount = 0;
    self.requestedCount = 0;
    self.finishedCount = 0;
    [self.manager cancelAll];
}

@end
