//
//  VideoEncoder.h
//  YSM-VideoToolBox
//
//  Created by 忆思梦 on 2017/1/3.
//  Copyright © 2017年 忆思梦. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <UIKit/UIKit.h>

@interface VideoEncoder : NSObject

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)endEncode;

@end
