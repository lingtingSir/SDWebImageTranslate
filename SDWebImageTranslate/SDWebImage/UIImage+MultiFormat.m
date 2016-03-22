//
//  UIImage+MultiFormat.m
//  SDWebImage
//
//  Created by Olivier Poitrey on 07/06/13.
//  Copyright (c) 2013 Dailymotion. All rights reserved.
//

#import "UIImage+MultiFormat.h"
#import "UIImage+GIF.h"
#import "NSData+ImageContentType.h"
#import <ImageIO/ImageIO.h>

#ifdef SD_WEBP
#import "UIImage+WebP.h"
#endif

@implementation UIImage (MultiFormat)

+ (UIImage *)sd_imageWithData:(NSData *)data {
    UIImage *image;
    NSString *imageContentType = [NSData sd_contentTypeForImageData:data];
    if ([imageContentType isEqualToString:@"image/gif"]) {
        // 1.如果是gif，使用gif的data转UIImage方法
        image = [UIImage sd_animatedGIFWithData:data];
    }
#ifdef SD_WEBP
    else if ([imageContentType isEqualToString:@"image/webp"])
    {
        // 2.如果是WebP，使用WebP的data转UIImage方法
        image = [UIImage sd_imageWithWebPData:data];
    }
#endif
    else { // 3.其他情况
        image = [[UIImage alloc] initWithData:data];
        // 获取图片的方向
        UIImageOrientation orientation = [self sd_imageOrientationFromImageData:data];
        if (orientation != UIImageOrientationUp) {
            // 如果方向不是向上，则使用方向重新创建图片
            /**
             *  需要说明的是：在其他情况的处理上的一些细节，
             SD会先获取到图片的原始方向，如果方向不是UIImageOrientationUp，使用UIImage的imageWithCGImage:scale:orientation方法创建图片，这个方法内部会按照传递的方向值将图片还原为正常的显示效果。 举例来说，如果拍摄时相机摆放角度为逆时针,旋转90度(对应着的EXIF值为8)，拍摄出来的图片显示效果为顺时针,旋转了90度(这就好比在查看时相机又摆正了，实际上在windows下的图片查看器显示为顺时针旋转了90度，而mac由于会自动处理则正向显示)，而如果使用UIImage的-imageWithCGImage:scale:orientation:方法创建图片，则会正向显示也就是实际拍摄时的效果。在网上有很多介绍如何获取正向图片的方法，它们的思路大多是这样：根据图片的方向值来逆向旋转图片。殊不知，apple早就为你提供好了
             -imageWithCGImage:scale:orientation:
             方法来直接创建出一个可正常显示的图片。
             */
            image = [UIImage imageWithCGImage:image.CGImage
                                        scale:image.scale
                                  orientation:orientation];
        }
    }


    return image;
}

// 获取图片的方向
+(UIImageOrientation)sd_imageOrientationFromImageData:(NSData *)imageData {
    UIImageOrientation result = UIImageOrientationUp;
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    if (imageSource) {
        // 获取这一帧的属性字典
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
        if (properties) {
            CFTypeRef val;
            int exifOrientation;
            val = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
            if (val) {
                CFNumberGetValue(val, kCFNumberIntType, &exifOrientation);
                result = [self sd_exifOrientationToiOSOrientation:exifOrientation];
            } // else - if it's not set it remains at up
            CFRelease((CFTypeRef) properties);
        } else {
            //NSLog(@"NO PROPERTIES, FAIL");
        }
        CFRelease(imageSource);
    }
    return result;
}

#pragma mark EXIF orientation tag converter
// Convert an EXIF image orientation to an iOS one.
// reference see here: http://sylvana.net/jpegcrop/exif_orientation.html

// 图片的EXIF信息会记录拍摄的角度，SD会从图片数据中读取出EXIF信息，由于EXIF值与方向一一对应(EXIF值-1 = 方向)，那么就使用
+ (UIImageOrientation) sd_exifOrientationToiOSOrientation:(int)exifOrientation {
    UIImageOrientation orientation = UIImageOrientationUp;
    switch (exifOrientation) {
        case 1:
            orientation = UIImageOrientationUp;
            break;

        case 3:
            orientation = UIImageOrientationDown;
            break;

        case 8:
            orientation = UIImageOrientationLeft;
            break;

        case 6:
            orientation = UIImageOrientationRight;
            break;

        case 2:
            orientation = UIImageOrientationUpMirrored;
            break;

        case 4:
            orientation = UIImageOrientationDownMirrored;
            break;

        case 5:
            orientation = UIImageOrientationLeftMirrored;
            break;

        case 7:
            orientation = UIImageOrientationRightMirrored;
            break;
        default:
            break;
    }
    return orientation;
}



@end
