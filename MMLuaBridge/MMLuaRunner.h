//
//  MMLuaRunner.h
//  MMLuaRunner
//
//  Created by yangzexin on 6/5/15.
//  Copyright (c) 2015 yangzexin. All rights reserved.
//

#import <Foundation/Foundation.h>

OBJC_EXPORT NSString *MMLuaRecognizableString(NSString *string);
OBJC_EXPORT NSString *MMRestoreLuaRecognizableString(NSString *luaRecognizableString);

@interface MMLuaReturn : NSObject

@property (nonatomic, copy, readonly) NSString *value;
@property (nonatomic, copy, readonly) NSString *error;

@end

@interface MMLuaRunner : NSObject

- (id)initWithScripts:(NSString *)scripts;

- (MMLuaReturn *)runFunction:(NSString *)name parameters:(NSString *)firstParameter, ... NS_REQUIRES_NIL_TERMINATION;

@end
