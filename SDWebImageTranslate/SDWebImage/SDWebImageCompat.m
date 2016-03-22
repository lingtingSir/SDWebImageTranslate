//
//  SDWebImageCompat.m
//  SDWebImage
//
//  Created by Olivier Poitrey on 11/12/12.
//  Copyright (c) 2012 Dailymotion. All rights reserved.

/**
 
 * 为什么在block回调图片之前要使用SDScaledImageForKey方法缩放图片呢
 * 举个例子吧，我们在命名图片的时候都是以xxxx@2x.png、xxxx@3x.png结尾的，但是我们在创建Image的时候并不需要在后面添加倍数，只需调用[UIImage imageNamed:@"xxxx"]即可，因为Xcode会帮我们根据当前分比率自动添加后缀倍数。如果你有一张72*72的二倍图片，当你以[UIImage imageNamed:@"xxxx@2x"]的方法加载图片的时候，你会发现图片被拉伸了，它的大小变为144*144了，这是因为Xcode自动添加二部后，以xxxx@2x@2x去查找图片，当它找不到的时候就把xxxx@2x图片当做一倍图片处理，所以图片的size就变大了，所以SDScaledImageForKey方法就是解决这件事情，以防url里面包含@"2x"、@"3x"等字符串，从而使图片size变大。
 */

//

#import "SDWebImageCompat.h"

#if !__has_feature(objc_arc)
#error SDWebImage is ARC only. Either turn on ARC for the project or use -fobjc-arc flag
#endif

/**
 *  缩放图片
 *
 *  @param key   key URL
 *  @param image 图片
 *
 *  @return return value description
 */
inline UIImage *SDScaledImageForKey(NSString *key, UIImage *image) {
    if (!image) {
        return nil;
    }
    
    if ([image.images count] > 0) {
        NSMutableArray *scaledImages = [NSMutableArray array];
        // 递归遍历
        for (UIImage *tempImage in image.images) {
            [scaledImages addObject:SDScaledImageForKey(key, tempImage)];
        }
        // 获取图片
        return [UIImage animatedImageWithImages:scaledImages duration:image.duration];
    }
    else {
        // 获取缩放比例
        if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
            CGFloat scale = 1.0;
            if (key.length >= 8) {
                // Search @2x. at the end of the string, before a 3 to 4 extension length (only if key len is 8 or more @2x. + 4 len ext)
                NSRange range = [key rangeOfString:@"@2x." options:0 range:NSMakeRange(key.length - 8, 5)];
                if (range.location != NSNotFound) {
                    scale = 2.0;
                }
            }
            // 获取图片
            UIImage *scaledImage = [[UIImage alloc] initWithCGImage:image.CGImage scale:scale orientation:image.imageOrientation];
            image = scaledImage;
        }
        return image;
    }
}
