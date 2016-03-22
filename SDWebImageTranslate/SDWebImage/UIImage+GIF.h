//
//  UIImage+GIF.h
//  LBGIFImage
//
//  Created by Laurin Brandner on 06.01.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIImage (GIF)


/**
 iOS展示gif图的原理：
 1.将gif图的每一帧导出为一个UIImage，将所有导出的UIImage放置到一个数组
 2.用上面的数组作为构造参数，使用animatedImage开头的方法创建UIImage，此时创建的UIImage的images属性值就是刚才的数组，duration值是它的一次播放时长。
 3.将UIImageView的image设置为上面的UIImage时，gif图会自动显示出来。(也就是说关键是那个数组，用尺寸相同的图片创建UIImage组成数组也是可以的)
 */

+ (UIImage *)sd_animatedGIFNamed:(NSString *)name;

// 将gif文件的二进制转为animatedImage
+ (UIImage *)sd_animatedGIFWithData:(NSData *)data;

// 将self.images数组中的图片按照指定的尺寸缩放，返回一个animatedImage，一次播放的时间是self.duration
- (UIImage *)sd_animatedImageByScalingAndCroppingToSize:(CGSize)size;

@end
