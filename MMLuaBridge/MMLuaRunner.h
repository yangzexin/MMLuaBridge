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

@protocol MMLuaModuleSupport <NSObject>

@optional
- (NSString *)scriptForModuleName:(NSString *)moduleName;

@end

@interface MMLuaRunnerServiceRequest : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *parameters;

@end

@interface MMLuaRunnerServiceResponse : NSObject

- (void)sendFeedbackWithValue:(NSString *)value error:(NSString *)error;

@end

@protocol MMLuaRunnerNativeServiceHandler <NSObject>

- (void)handleWithRequest:(MMLuaRunnerServiceRequest *)request response:(MMLuaRunnerServiceResponse *)response;
- (void)cancel;

@end

@interface MMLuaRunnerServiceControl : NSObject

- (void)cancel;

@end

@interface MMLuaRunner : NSObject

@property (nonatomic, assign, readonly) NSUInteger uid;

+ (void)setSharedModuleSupport:(id<MMLuaModuleSupport>)moduleSupport;
+ (id<MMLuaModuleSupport>)sharedModuleSupport;

- (id)initWithScripts:(NSString *)scripts;

- (MMLuaReturn *)callFunctionWithName:(NSString *)name parameters:(NSArray *)parameters;

- (MMLuaRunnerServiceControl *)requestLuaService:(NSString *)service parameters:(NSDictionary *)parameters completion:(void(^)(MMLuaReturn *ret))completion;

- (void)registerNativeService:(NSString *)service handlerBuilder:(id<MMLuaRunnerNativeServiceHandler>(^)(void))handlerBuilder;

- (void)unregisterLocalService:(NSString *)service;

@end
