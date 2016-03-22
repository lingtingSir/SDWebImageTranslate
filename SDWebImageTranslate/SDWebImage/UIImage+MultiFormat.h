//
//  UIImage+MultiFormat.h
//  SDWebImage
//
//  Created by Olivier Poitrey on 07/06/13.
//  Copyright (c) 2013 Dailymotion. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIImage (MultiFormat)

// 根据NSData相应的MIME将NSData转为UIImage
+ (UIImage *)sd_imageWithData:(NSData *)data;

@end
