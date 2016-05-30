//  FSImageViewer
//
//  Created by Felix Schulze on 8/26/2013.
//  Copyright 2013 Felix Schulze. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "DSEGOCache.h"
#import <CommonCrypto/CommonDigest.h>
#import "DSFSImageLoader.h"
#import "DSAFHTTPRequestOperation.h"

@implementation DSFSImageLoader {
    NSMutableArray *runningRequests;
}

+ (DSFSImageLoader *)sharedInstance {
    static DSFSImageLoader *sharedInstance = nil;
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DSFSImageLoader alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.timeoutInterval = 30.0;
        runningRequests = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void)dealloc {
    [self cancelAllRequests];
}

- (void)cancelAllRequests {
    for (DSAFHTTPRequestOperation *imageRequestOperation in runningRequests) {
        [imageRequestOperation cancel];
    }
}

- (void)cancelRequestForUrl:(NSURL *)aURL {
    for (DSAFHTTPRequestOperation *imageRequestOperation in runningRequests) {
        if ([imageRequestOperation.request.URL isEqual:aURL]) {
            [imageRequestOperation cancel];
            break;
        }
    }
}

- (void)loadImageForURL:(NSURL *)aURL progress:(void (^)(float progress))progress image:(void (^)(UIImage *image, NSError *error))imageBlock {

    if (!aURL) {
        NSError *error = [NSError errorWithDomain:@"de.felixschulze.fsimageloader" code:412 userInfo:@{
                NSLocalizedDescriptionKey : @"You must set a url"
        }];
        imageBlock(nil, error);
    };
    
    NSString *urlString = [[aURL absoluteString] copy];
    NSData *data = [urlString dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *urlStringSha1 = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [urlStringSha1 appendFormat:@"%02x", digest[i]];
    }
    NSString *cacheKey = [NSString stringWithFormat:@"DSFSImageLoader-%@", [urlStringSha1 copy]];
    UIImage *anImage = [[DSEGOCache globalCache] imageForKey:cacheKey];
    
    if (!anImage) {
        // Deprecated cacheKey
        NSString *deprecatedCacheKey = [NSString stringWithFormat:@"DSFSImageLoader-%lu", (unsigned long) [[aURL description] hash]];
        anImage = [[DSEGOCache globalCache] imageForKey:deprecatedCacheKey];
    }


    if (anImage) {
        if (imageBlock) {
            imageBlock(anImage, nil);
        }
    }
    else {
        [self cancelRequestForUrl:aURL];

        NSURLRequest *urlRequest = [[NSURLRequest alloc] initWithURL:aURL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:_timeoutInterval];
        DSAFHTTPRequestOperation *imageRequestOperation = [[DSAFHTTPRequestOperation alloc] initWithRequest:urlRequest];
        imageRequestOperation.responseSerializer = [DSAFImageResponseSerializer serializer];
        [runningRequests addObject:imageRequestOperation];
        __weak DSAFHTTPRequestOperation *imageRequestOperationForBlock = imageRequestOperation;

        [imageRequestOperation setCompletionBlockWithSuccess:^(DSAFHTTPRequestOperation *operation, id responseObject) {
            UIImage *image = responseObject;
            [[DSEGOCache globalCache] setImage:image forKey:cacheKey];
            if (imageBlock) {
                imageBlock(image, nil);
            }
            [runningRequests removeObject:imageRequestOperationForBlock];
        } failure:^(DSAFHTTPRequestOperation *operation, NSError *error) {
            if (imageBlock) {
                imageBlock(nil, error);
            }
            [runningRequests removeObject:imageRequestOperationForBlock];
        }];
        
        [imageRequestOperation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
            if (progress) {
                progress((float)totalBytesRead / totalBytesExpectedToRead);
            }
        }];
        
        [imageRequestOperation start];
    }
}

@end