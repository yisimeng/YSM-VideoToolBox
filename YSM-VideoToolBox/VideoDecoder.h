//
//  VideoDecoder.h
//  YSM-VideoToolBox
//
//  Created by 忆思梦 on 2017/1/4.
//  Copyright © 2017年 忆思梦. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

typedef void(^VideoDecodeCompleteBlock)(CVPixelBufferRef pixelBuffer);

@interface VideoDecoder : NSObject

- (void)decodeWithPath:(NSString *)path complete:(VideoDecodeCompleteBlock)complete;

@end
