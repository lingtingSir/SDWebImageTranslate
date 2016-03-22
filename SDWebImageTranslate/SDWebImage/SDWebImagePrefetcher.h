/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 SDWebImagePrefetcher用来预取图片的。它用GCD在主线程中通过SDWebImageManager来预取图片，并通过delegate和block回到相关状态和进度。
 */

#import <Foundation/Foundation.h>
#import "SDWebImageManager.h"

@class SDWebImagePrefetcher;

@protocol SDWebImagePrefetcherDelegate <NSObject>

@optional

/**
 * Called when an image was prefetched.
 *
 * @param imagePrefetcher The current image prefetcher
 * @param imageURL        The image url that was prefetched
 * @param finishedCount   The total number of images that were prefetched (successful or not)
 * @param totalCount      The total number of images that were to be prefetched
 */

/**
 *  当一个图像被预取。
 *
 *  @param imagePrefetcher 当前图像预取
 *  @param imageURL        图像URL进行预取
 *  @param finishedCount   总数图像进行预取
 *  @param totalCount      总数的图像被预取
 */
- (void)imagePrefetcher:(SDWebImagePrefetcher *)imagePrefetcher didPrefetchURL:(NSURL *)imageURL finishedCount:(NSUInteger)finishedCount totalCount:(NSUInteger)totalCount;

/**
 * Called when all images are prefetched.
 * @param imagePrefetcher The current image prefetcher
 * @param totalCount      The total number of images that were prefetched (whether successful or not)
 * @param skippedCount    The total number of images that were skipped
 */


/**
 *  当所有图像预取
 *
 *  @param imagePrefetcher 当前图像的预取器
 *  @param totalCount      总数量的图像，预取（无论成功与否）
 *  @param skippedCount    skippedcount总数的图像被跳过
 */
- (void)imagePrefetcher:(SDWebImagePrefetcher *)imagePrefetcher didFinishWithTotalCount:(NSUInteger)totalCount skippedCount:(NSUInteger)skippedCount;

@end

// 
typedef void(^SDWebImagePrefetcherProgressBlock)(NSUInteger noOfFinishedUrls, NSUInteger noOfTotalUrls);


/**
 *  预存完成的block
 *
 *  @param noOfFinishedUrls 预存成功的url
 *  @param noOfSkippedUrls  被跳过图像
 */
typedef void(^SDWebImagePrefetcherCompletionBlock)(NSUInteger noOfFinishedUrls, NSUInteger noOfSkippedUrls);

/**
 * Prefetch some URLs in the cache for future use. Images are downloaded in low priority.
 */

/**
 *  预取一些网址在未来使用的缓存。图像被下载的低优先级。
 */
@interface SDWebImagePrefetcher : NSObject

/**
 *  The web image manager
 */
@property (strong, nonatomic, readonly) SDWebImageManager *manager;

/**
 * Maximum number of URLs to prefetch at the same time. Defaults to 3.
 */

/**
 *  预取同时URL的最大数量。默认为3。
 */
@property (nonatomic, assign) NSUInteger maxConcurrentDownloads;

/**
 * SDWebImageOptions for prefetcher. Defaults to SDWebImageLowPriority.
 */

/**
 *  SDWebImageOptions 预取器。默认sdwebimagelowpriority。低优先级
 */
@property (nonatomic, assign) SDWebImageOptions options;

@property (weak, nonatomic) id <SDWebImagePrefetcherDelegate> delegate;

/**
 * Return the global image prefetcher instance.
 */

/**
 *  返回全局图像的预取器实例。
 *
 *  @return 返回全局图像的预取器实例。
 */
+ (SDWebImagePrefetcher *)sharedImagePrefetcher;

/**
 * Assign list of URLs to let SDWebImagePrefetcher to queue the prefetching,
 * currently one image is downloaded at a time,
 * and skips images for failed downloads and proceed to the next image in the list
 *
 * @param urls list of URLs to prefetch
 */

/**
 *指定的URL列表让sdwebimageprefetcher排队预取，
 *当前一个图像被下载的时间，
 *跳过失败的下载图像进行到下一个图像列表中
 *
 * @param URL的URL列表预取
 */
- (void)prefetchURLs:(NSArray *)urls;

/**
 * Assign list of URLs to let SDWebImagePrefetcher to queue the prefetching,
 * currently one image is downloaded at a time,
 * and skips images for failed downloads and proceed to the next image in the list
 *
 * @param urls            list of URLs to prefetch
 * @param progressBlock   block to be called when progress updates; 
 *                        first parameter is the number of completed (successful or not) requests, 
 *                        second parameter is the total number of images originally requested to be prefetched
 * @param completionBlock block to be called when prefetching is completed
 *                        first param is the number of completed (successful or not) requests,
 *                        second parameter is the number of skipped requests
 */


/**
 *指定的URL列表，让SDWebImagePrefetcher排队的预取，
 *目前一个图像在同一时间下载，
 *和跳过图片失败的下载，并继续到下一个图像列表中
 *
 URL到预取的
 *@参数的URL列表
 * @参数progressBlock块被调用时进度更新;
 *第一个参数是完成（成功或失败）的请求数，
 *第二个参数是最初请求的图像的总数要预取完成预取时调用
 *@参数completionBlock块
 *第一个参数是完成（成功或失败）的请求数，
 *第二个参数是跳过请求数
 */
- (void)prefetchURLs:(NSArray *)urls progress:(SDWebImagePrefetcherProgressBlock)progressBlock completed:(SDWebImagePrefetcherCompletionBlock)completionBlock;

/**
 * Remove and cancel queued list
 */

/**
 *  删除并取消排队名单
 */
- (void)cancelPrefetching;


@end
