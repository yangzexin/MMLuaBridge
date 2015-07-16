//
//  MMLuaRunner.m
//  MMLuaRunner
//
//  Created by yangzexin on 6/5/15.
//  Copyright (c) 2015 yangzexin. All rights reserved.
//

#import "MMLuaRunner.h"

#import "lua.h"
#import "lualib.h"
#import "lauxlib.h"

@interface MMLuaRunnerManager : NSObject

+ (instancetype)sharedManager;

- (MMLuaRunner *)findRunnerByLuaState:(lua_State *)luaState;

@end

#pragma mark - MMLuaRunnerServiceRequest
@interface MMLuaRunnerServiceRequest()

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *parameters;

@end

@implementation MMLuaRunnerServiceRequest

@end

@interface MMLuaRunnerServiceResponse ()

@property (nonatomic, copy) void(^whenSendFeedback)(NSString *, NSString *);

@end

@implementation MMLuaRunnerServiceResponse

- (void)sendFeedbackWithValue:(NSString *)value error:(NSString *)error
{
    self.whenSendFeedback(value, error);
}

@end

@interface MMBlockWrapper : NSObject

@property (nonatomic, copy) id block;

@end

@implementation MMBlockWrapper

@end

#pragma mark - MMLuaAsyncServiceSupport
@interface MMLuaAsyncServiceSupport : NSObject

+ (instancetype)sharedSupport;

@end

@interface MMLuaAsyncServiceSupport ()

@property (nonatomic, strong) NSMutableDictionary *keyCallbackIdValueComletionBlock;

@property (nonatomic, strong) NSMutableDictionary *keyServiceNameValueHandlerBuilder;
@property (nonatomic, strong) NSMutableDictionary *keyCallbackidValueHandlerInstance;

@end

@implementation MMLuaAsyncServiceSupport

+ (instancetype)sharedSupport {
    static id instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [self new];
    });
    
    return instance;
}

- (id)init {
    self = [super init];
    
    self.keyCallbackIdValueComletionBlock = [NSMutableDictionary dictionary];
    self.keyServiceNameValueHandlerBuilder = [NSMutableDictionary dictionary];
    self.keyCallbackidValueHandlerInstance = [NSMutableDictionary dictionary];
    
    return self;
}

- (NSString *)addRequestServiceCompletion:(void(^)(MMLuaReturn *ret))completion {
    NSString *callbackId = [NSString stringWithFormat:@"%f", [NSDate timeIntervalSinceReferenceDate]];
    
    [self.keyCallbackIdValueComletionBlock setObject:({
        MMBlockWrapper *wrapper = [MMBlockWrapper new];
        wrapper.block = completion;
        
        wrapper;
    }) forKey:callbackId];
    
    return callbackId;
}

- (void(^)(MMLuaReturn *))requestServiceCompletionForCallbackId:(NSString *)callbackId {
    MMBlockWrapper *wrapper = [self.keyCallbackIdValueComletionBlock objectForKey:callbackId];
    
    return wrapper.block;
}

- (void)removeRequestServiceCompletionWithCallbackId:(NSString *)callbackId {
    [self.keyCallbackIdValueComletionBlock removeObjectForKey:callbackId];
}

- (void)registerLocalService:(NSString *)service handlerBuilder:(id<MMLuaRunnerLocalServiceHandler>(^)())handlerBuilder {
    [self.keyServiceNameValueHandlerBuilder setObject:({
        MMBlockWrapper *wrapper = [MMBlockWrapper new];
        wrapper.block = handlerBuilder;
        
        wrapper;
    }) forKey:service];
}

- (void)unregisterLocalService:(NSString *)service {
    [self.keyServiceNameValueHandlerBuilder removeObjectForKey:service];
}

- (void)applyServiceWithLuaState:(lua_State *)luaState service:(NSString *)service callbackid:(NSString *)callbackid params:(NSString *)params {
    MMBlockWrapper *wrapper = [self.keyServiceNameValueHandlerBuilder objectForKey:service];
    if (wrapper) {
        id<MMLuaRunnerLocalServiceHandler>(^handlerBuilder)() = wrapper.block;
        id<MMLuaRunnerLocalServiceHandler> handler = handlerBuilder();
        
        MMLuaRunnerServiceRequest *request = [MMLuaRunnerServiceRequest new];
        request.name = service;
        request.parameters = params;
        
        MMLuaRunnerServiceResponse *response = [MMLuaRunnerServiceResponse new];
        [response setWhenSendFeedback:^(NSString *value, NSString *error) {
            id<MMLuaRunnerLocalServiceHandler> handler = [self.keyCallbackidValueHandlerInstance objectForKey:callbackid];
            if (handler) {
                MMLuaRunner *runner = [[MMLuaRunnerManager sharedManager] findRunnerByLuaState:luaState];
                if (value == nil) {
                    value = @"";
                }
                if (error == nil) {
                    error= @"";
                }
                [runner callFunctionWithName:@"asyncservice_callback" parameters:@[callbackid, value, error]];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.keyCallbackidValueHandlerInstance removeObjectForKey:callbackid];
                });
            }
        }];
        
        [self.keyCallbackidValueHandlerInstance setObject:handler forKey:callbackid];
        
        [handler handleWithRequest:request response:response];
    } else {
        NSString *error = [NSString stringWithFormat:@"LUA ERROR: unknown Objc service: %@", service];
#ifdef DEBUG
        NSLog(@"%@", error);
#endif
        MMLuaRunner *runner = [[MMLuaRunnerManager sharedManager] findRunnerByLuaState:luaState];
        [runner callFunctionWithName:@"asyncservice_callback" parameters:@[callbackid, @"", error]];
    }
}

- (void)cancelServiceWithCallbackid:(NSString *)callbackid {
    id<MMLuaRunnerLocalServiceHandler> handler = [self.keyCallbackidValueHandlerInstance objectForKey:callbackid];
    [handler cancel];
    [self.keyCallbackidValueHandlerInstance removeObjectForKey:callbackid];
}

@end

#pragma mark - MMLuaReturn
@interface MMLuaReturn ()

@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *error;

@end

@implementation MMLuaReturn

+ (instancetype)returnWithValue:(NSString *)value {
    MMLuaReturn *ret = [MMLuaReturn new];
    ret.value = value;
    
    return ret;
}

+ (instancetype)returnWithError:(NSString *)error {
    MMLuaReturn *ret = [MMLuaReturn new];
    ret.error = error;
    
    return ret;
}

- (NSString *)description {
    return self.error == nil ? self.value : self.error;
}

@end

@interface _MMLuaRunnerModuleSupportFromMainBundle : NSObject <MMLuaModuleSupport>

@end

@implementation _MMLuaRunnerModuleSupportFromMainBundle

- (NSString *)scriptForModuleName:(NSString *)moduleName {
    return [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:moduleName ofType:@"lua"] encoding:NSUTF8StringEncoding error:nil];
}

@end

@interface MMLuaRunnerConfiguration : NSObject

@property (nonatomic, strong) id<MMLuaModuleSupport> moduleSupport;

@property (nonatomic, strong) NSMutableDictionary *keyModuleNameValueScript;

+ (instancetype)sharedConfiguration;

@end

@implementation MMLuaRunnerConfiguration

+ (instancetype)sharedConfiguration {
    static id instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [self new];
    });
    
    return instance;
}

- (id)init {
    self = [super init];
    
    self.keyModuleNameValueScript = [NSMutableDictionary dictionary];
    self.moduleSupport = [_MMLuaRunnerModuleSupportFromMainBundle new];
    
    return self;
}

- (NSString *)cachedModuleWithName:(NSString *)moduleName {
    return [self.keyModuleNameValueScript objectForKey:moduleName];
}

- (void)setModuleCacheWithName:(NSString *)moduleName script:(NSString *)script {
    [self.keyModuleNameValueScript setObject:script forKey:moduleName];
}

@end

BOOL _SingleCharIsChinese(NSString *str) {
    int firstChar = [str characterAtIndex:0];
    if(firstChar >= 0x4e00 && firstChar <= 0x9FA5){
        return YES;
    }
    
    return NO;
}

BOOL _StringContainsChinese(NSString *str)
{
    BOOL contains = NO;
    for(NSInteger i = 0; i < [str length]; ++i){
        NSString *sub = [str substringWithRange:NSMakeRange(i, 1)];
        if(_SingleCharIsChinese(sub)){
            contains = YES;
            break;
        }
    }
    
    return contains;
}

#pragma mark - Lua CFuncions
NSString *luaStringParam(lua_State *L, int location) {
    const char *paramValue = lua_tostring(L, location);
    NSString *paramString = @"";
    if(paramValue){
        paramString = [NSString stringWithFormat:@"%s", paramValue];
    }
    paramString = MMRestoreLuaRecognizableString(paramString);
    if(paramString.length == 0){
        paramString = @"";
    }
    
    return paramString;
}

void pushString(lua_State *L, NSString *returnValue) {
    returnValue = MMLuaRecognizableString(returnValue);
    lua_pushstring(L, [returnValue UTF8String]);
}

int ustring_substring(lua_State *L) {
    NSString *string = luaStringParam(L, 1);
    NSInteger beginIndex = [luaStringParam(L, 2) intValue];
    NSInteger endIndex = [luaStringParam(L, 3) intValue];
    
    NSString *resultString = @"";
    if(string.length != 0 && beginIndex <= string.length && endIndex <= string.length && beginIndex < endIndex){
        resultString = [string substringWithRange:NSMakeRange(beginIndex, endIndex - beginIndex)];
    }
    pushString(L, resultString);
    
    return 1;
}

int ustring_length(lua_State *L) {
    NSString *string = luaStringParam(L, 1);
    lua_pushnumber(L, [string length]);
    
    return 1;
}

int ustring_find(lua_State *L) {
    NSString *string = luaStringParam(L, 1);
    NSString *targetStr = luaStringParam(L, 2);
    NSInteger fromIndex = lua_tointeger(L, 3);
    NSInteger reverse = lua_toboolean(L, 4);
    
    NSInteger location = -1;
    if(string.length > 0 && targetStr.length > 0 && fromIndex > -1 && fromIndex < string.length){
        NSRange tmpRange = [string rangeOfString:targetStr
                                         options:reverse == 1 ? NSBackwardsSearch : NSCaseInsensitiveSearch
                                           range:reverse == 1 ? NSMakeRange(0, fromIndex) : NSMakeRange(fromIndex, string.length - fromIndex)];
        location = tmpRange.location == NSNotFound ? -1 : tmpRange.location;
    }
    lua_pushnumber(L, location);
    
    return 1;
}

int ustring_encodeURL(lua_State *L) {
    NSString *str = luaStringParam(L, 1);
    if(str.length != 0){
        CFStringRef urlString = CFURLCreateStringByAddingPercentEscapes(NULL,(CFStringRef)str, NULL,(CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8);
        str = (__bridge NSString *)urlString;
        CFAutorelease(urlString);
    }
    pushString(L, str);
    
    return 1;
}

int ustring_replace(lua_State *L) {
    NSString *string = luaStringParam(L, 1);
    NSString *occurrences = luaStringParam(L, 2);
    NSString *replacement = luaStringParam(L, 3);
    string = [string stringByReplacingOccurrencesOfString:occurrences withString:replacement];
    pushString(L, string);
    
    return 1;
}

int sys_log(lua_State *L) {
    NSString *string = luaStringParam(L, 1);
    
    NSLog(@"%@", string);
    
    return 0;
}

int async_service_callback(lua_State *L) {
    NSString *callbackId = luaStringParam(L, 1);
    NSString *value = luaStringParam(L, 2);
    NSString *error = luaStringParam(L, 3);
    
    void(^completion)(MMLuaReturn *) = [[MMLuaAsyncServiceSupport sharedSupport] requestServiceCompletionForCallbackId:callbackId];
    if (completion) {
        if (error.length != 0) {
            completion([MMLuaReturn returnWithError:error]);
        } else {
            completion([MMLuaReturn returnWithValue:value]);
        }
    }
    [[MMLuaAsyncServiceSupport sharedSupport] removeRequestServiceCompletionWithCallbackId:callbackId];
    
    return 0;
}

int async_service_apply(lua_State *L) {
    NSString *servicename = luaStringParam(L, 1);
    NSString *callbackid = luaStringParam(L, 2);
    NSString *params = luaStringParam(L, 3);
    
    [[MMLuaAsyncServiceSupport sharedSupport] applyServiceWithLuaState:L service:servicename callbackid:callbackid params:params];
    
    return 0;
}

int async_service_cancel(lua_State *L) {
    NSString *callbackid = luaStringParam(L, 1);
    [[MMLuaAsyncServiceSupport sharedSupport] cancelServiceWithCallbackid:callbackid];
    
    return 0;
}

#pragma mark - Interaction Utils
static char *CustomHexList = "0123456789abcdef";

char _CustomHexCharForByte(unsigned char c) {
    return *(CustomHexList + c);
}

unsigned char _ByteForCustomHexChar(char c) {
    size_t len = strlen(CustomHexList);
    for(int i = 0; i < len; ++i){
        if(c == *(CustomHexList + i)){
            return i;
        }
    }
    
    return 0;
}

NSString *_HexStringByEncodingData(NSData *data) {
    char *bytes = malloc(sizeof(unsigned char) * [data length]);
    [data getBytes:bytes length:data.length];
    
    size_t len = sizeof(char) * [data length] * 2 + 1;
    char *result = malloc(len);
    for(int i = 0; i < [data length]; ++i){
        unsigned char tmp = *(bytes + i);
        unsigned char low = tmp & 0xF;
        unsigned char high = (tmp & 0xF0) >> 4;
        *(result + i * 2) = _CustomHexCharForByte(low);
        *(result + i * 2 + 1) = _CustomHexCharForByte(high);
    }
    free(bytes);
    
    *(result + len - 1) = '\0';
    
    NSString *str = [NSString stringWithUTF8String:result];
    free(result);
    
    return str;
}

NSString *_EncodeUnichar(unichar unich) {
    unsigned char low = unich & 0xFF;
    unsigned char high = ((unich & 0xFF00) >> 8);
    unsigned char bytes[] = {low, high};
    NSData *data = [NSData dataWithBytes:bytes length:2];
    NSString *str = _HexStringByEncodingData(data);
    
    return str;
}

NSString *_HexStringByEncodingString(NSString *string) {
    if([string isEqualToString:@""]){
        return @"";
    }
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    
    return _HexStringByEncodingData(data);
}

NSData *_DataByDecodingHexString(NSString *string) {
    if([string isEqualToString:@""]){
        return nil;
    }
    if([string length] % 2 != 0){
        return nil;
    }
    size_t resultBytesLen = sizeof(char) * [string length] / 2;
    char *resultBytes = malloc(resultBytesLen);
    
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    char *bytes = malloc(sizeof(char) * [data length]);
    [data getBytes:bytes length:data.length];
    for(int i = 0, j = 0; i < [data length]; i += 2, ++j){
        unsigned char low = _ByteForCustomHexChar(*(bytes + i));
        unsigned char high = _ByteForCustomHexChar(*(bytes + i + 1));
        unsigned char tmp = ((high << 4) & 0xF0) + low;
        *(resultBytes + j) = tmp;
    }
    
    free(bytes);
    
    NSData *resultData = [NSData dataWithBytes:resultBytes length:resultBytesLen];
    free(resultBytes);
    
    return resultData;
}

NSString *_RestoreUnichar(NSString *str) {
    NSData *data = _DataByDecodingHexString(str);
    unsigned char bytes[2];
    [data getBytes:bytes length:2];
    unichar unich = bytes[0] + (bytes[1] << 8);
    unichar unichars[1] = {unich};
    
    return [NSString stringWithCharacters:unichars length:1];
}



NSString *MMLuaRecognizableString(NSString *string) {
    NSMutableString *allString = [NSMutableString string];
    for(NSInteger i = 0; i < string.length; i++){
        const unichar ch = [string characterAtIndex:i];
        if(ch > 255){
            [allString appendFormat:@"[u]%@[/u]", _EncodeUnichar(ch)];
        }else{
            const unichar chs[1] = {ch};
            [allString appendString:[NSString stringWithCharacters:chs length:1]];
        }
    }
    
    return allString;
}

NSString *MMRestoreLuaRecognizableString(NSString *luaRecognizableString) {
    if(luaRecognizableString.length == 0){
        return @"";
    }
    NSMutableString *allString = [NSMutableString string];
    NSRange beginRange;
    NSRange endRange = NSMakeRange(0, luaRecognizableString.length);
    while(true){
        beginRange = [luaRecognizableString rangeOfString:@"[u]" options:NSCaseInsensitiveSearch range:endRange];
        if(beginRange.location == NSNotFound){
            if(endRange.location == 0){
                [allString appendString:luaRecognizableString];
            }else if(endRange.location != luaRecognizableString.length){
                [allString appendString:[luaRecognizableString substringFromIndex:endRange.location]];
            }
            break;
        }
        NSString *en = [luaRecognizableString substringWithRange:NSMakeRange(endRange.location, beginRange.location - endRange.location)];
        [allString appendString:en];
        beginRange.location += 3;
        beginRange.length = luaRecognizableString.length - beginRange.location;
        endRange = [luaRecognizableString rangeOfString:@"[/u]" options:NSCaseInsensitiveSearch range:beginRange];
        NSString *cn = [luaRecognizableString substringWithRange:NSMakeRange(beginRange.location, endRange.location - beginRange.location)];
        cn = _RestoreUnichar(cn);
        [allString appendString:cn];
        endRange.location += 4;
        endRange.length = luaRecognizableString.length - endRange.location;
    }
    
    return allString;
}

NSString *_FilterInputParameter(NSString *parameter) {
    if(_StringContainsChinese(parameter)){
        parameter = MMLuaRecognizableString(parameter);
    }
    
    return parameter;
}

NSString *_RestoreOutputValue(NSString *returnValue) {
    return MMRestoreLuaRecognizableString(returnValue);
}

void _PushFunctionToLua(lua_State *L, char *functionName, int (*func)(lua_State *L)) {
    lua_pushstring(L, functionName);
    lua_pushcfunction(L, func);
    lua_settable(L, LUA_GLOBALSINDEX);
}

void _AttachCFunctions(lua_State *L) {
    _PushFunctionToLua(L, "StringFind", ustring_find); // ustr_find(from_str, target_str, begin_index, reverse)
    _PushFunctionToLua(L, "StringLength", ustring_length);// ustr_len(str)
    _PushFunctionToLua(L, "StringSubstring", ustring_substring);// ustr_substr(begin_index, end_index)
    _PushFunctionToLua(L, "StringEncodeURL", ustring_encodeURL);// ustr_encodeURL(str)
    _PushFunctionToLua(L, "StringReplace", ustring_replace);// ustr_replace(str, target_str, replacement_str)
    
    _PushFunctionToLua(L, "print", sys_log);
    _PushFunctionToLua(L, "AsyncServiceCallback", async_service_callback);
    _PushFunctionToLua(L, "AsyncServiceApply", async_service_apply);
    _PushFunctionToLua(L, "AsyncServiceCancel", async_service_cancel);
}

int _RequireModuleSupport(lua_State *L) {
    const char *cmoduleName = luaL_checkstring(L, 1);
    
    if(strlen(cmoduleName) != 0){
        NSString *moduleName = [NSString stringWithCString:cmoduleName encoding:NSASCIIStringEncoding];
        
        NSString *targetScript = [[MMLuaRunnerConfiguration sharedConfiguration] cachedModuleWithName:moduleName];
        if (targetScript == nil) {
            id<MMLuaModuleSupport> moduleSupport = [[MMLuaRunnerConfiguration sharedConfiguration] moduleSupport];
            if (moduleSupport) {
                targetScript = [moduleSupport scriptForModuleName:moduleName];
                if (targetScript) {
                    targetScript = MMLuaRecognizableString(targetScript);
                    [[MMLuaRunnerConfiguration sharedConfiguration] setModuleCacheWithName:moduleName script:targetScript];
                }
            } else {
                NSLog(@"%@", [NSString stringWithFormat:@"LUA ERROR: can't find module support for module:%s", cmoduleName]);
            }
        }
        
        if(targetScript.length != 0){
            const char *cscript = [targetScript UTF8String];
            luaL_loadbuffer(L, cscript, [targetScript length], cmoduleName);
        }
    }
    
    return 1;
}

#pragma mark - MMLuaRunnerServiceControl
@interface MMLuaRunnerServiceControl ()

@property (nonatomic, copy) void(^didCancel)();

@end

@implementation MMLuaRunnerServiceControl

- (void)cancel {
    if (self.didCancel) {
        self.didCancel();
    }
}

@end

#pragma mark - MMLuaBridge
@interface MMLuaRunner () {
    char *_script;
    lua_State *_lua_state;
    NSLock *_luaLock;
}

- (lua_State *)luaState;

@end

@interface MMLuaRunnerWeakWrapper : NSObject

@property (nonatomic, weak) id runner;

@end

@implementation MMLuaRunnerWeakWrapper

@end

@interface MMLuaRunnerManager ()

@property (nonatomic, strong) NSMutableArray *runners;

@end

@implementation MMLuaRunnerManager

+ (instancetype)sharedManager {
    static id instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [self new];
    });
    
    return instance;
}

- (id)init {
    self = [super init];
    
    self.runners = [NSMutableArray array];
    
    return self;
}

- (void)addRunner:(MMLuaRunner *)runner {
    MMLuaRunnerWeakWrapper *wrapper = [MMLuaRunnerWeakWrapper new];
    wrapper.runner = runner;
    
    [self.runners addObject:wrapper];
}

- (void)removeRunner:(MMLuaRunner *)runner {
    NSArray *runners = [self.runners copy];
    for (MMLuaRunnerWeakWrapper *wrapper in runners) {
        if (wrapper.runner == runner) {
            [self.runners removeObject:wrapper];
            break;
        }
    }
}

- (MMLuaRunner *)findRunnerByLuaState:(lua_State *)luaState {
    MMLuaRunner *runner = nil;
    
    NSArray *runners = [self.runners copy];
    for (MMLuaRunnerWeakWrapper *wrapper in runners) {
        if ([wrapper.runner luaState] == luaState) {
            runner = wrapper.runner;
            break;
        }
    }
    
    return runner;
}

@end

@implementation MMLuaRunner

- (void)dealloc {
    if(_lua_state){
        lua_close(_lua_state);
    }
    
    if (_script) {
        free(_script);
    }
    
    [[MMLuaRunnerManager sharedManager] removeRunner:self];
}

- (lua_State *)luaState {
    return _lua_state;
}

+ (void)setSharedModuleSupport:(id<MMLuaModuleSupport>)moduleSupport {
    [[MMLuaRunnerConfiguration sharedConfiguration] setModuleSupport:moduleSupport];
}

+ (id<MMLuaModuleSupport>)sharedModuleSupport {
    return [[MMLuaRunnerConfiguration sharedConfiguration] moduleSupport];
}

- (id)initWithScripts:(NSString *)scripts {
    self = [super init];
    
    scripts = MMLuaRecognizableString(scripts);
    NSAssert(scripts.length != 0, @"LUA ERROR: scripts cannot be NULL");
    _script = malloc(sizeof(char *) * (scripts.length + 1));
    strcpy(_script, [scripts UTF8String]);

    [self _initLuaState];
    
    [[MMLuaRunnerManager sharedManager] addRunner:self];
    
    return self;
}

- (void)_initLuaState {
    if(_lua_state){
        lua_close(_lua_state);
    }
    _lua_state = lua_open();
    luaL_openlibs(_lua_state);
    
    lua_register(_lua_state, "require_module_support", _RequireModuleSupport);
    luaL_dostring(_lua_state, "table.insert(package.loaders, require_module_support)");
    
    if(luaL_dostring(_lua_state, _script)){
        // dostring error, lua cannot do this script
        const char *error = lua_tostring(_lua_state, -1);
        NSLog(@"LUA ERROR: failed to init lua_state {\n%s\n}", error);
    }
    
    _luaLock = [NSLock new];
}

- (MMLuaReturn *)runFunction:(NSString *)name params:(NSString *)firstParameter, ... NS_REQUIRES_NIL_TERMINATION {
    va_list args;
    NSMutableArray *parameters = [NSMutableArray array];
    if(firstParameter){
        va_start(args, firstParameter);
        for(NSString *tmpParameter = firstParameter; tmpParameter; tmpParameter = va_arg(args, id)){
            [parameters addObject:tmpParameter];
        }
        va_end(args);
    }
    
    return _CallLuaFunction(_luaLock, _lua_state, _script, name, parameters);
}

- (MMLuaReturn *)callFunctionWithName:(NSString *)name parameters:(NSArray *)parameters {
    return _CallLuaFunction(_luaLock, _lua_state, _script, name, parameters);
}

- (MMLuaRunnerServiceControl *)requestService:(NSString *)service parameters:(NSDictionary *)parameters completion:(void(^)(MMLuaReturn *ret))completion {
    NSString *callbackId = [[MMLuaAsyncServiceSupport sharedSupport] addRequestServiceCompletion:completion];
    NSString *json = @"";
    if (parameters) {
        json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:parameters options:0 error:nil] encoding:NSUTF8StringEncoding];
    }
    
    MMLuaReturn *ret = _CallLuaFunction(_luaLock, _lua_state, _script, @"asyncservice_apply", @[service, callbackId, json]);
    if (ret.error) {
        if (completion) {
            completion(ret);
        }
    }
    
    return ({
        MMLuaRunnerServiceControl *control = [MMLuaRunnerServiceControl new];
        
        [control setDidCancel:^{
            _CallLuaFunction(_luaLock, _lua_state, _script, @"asyncservice_cancel", @[callbackId]);
        }];
        
        control;
    });
}

- (void)registerLocalService:(NSString *)service handlerBuilder:(id<MMLuaRunnerLocalServiceHandler>(^)())handlerBuilder {
    [[MMLuaAsyncServiceSupport sharedSupport] registerLocalService:service handlerBuilder:handlerBuilder];
}

- (void)unregisterLocalService:(NSString *)service {
    [[MMLuaAsyncServiceSupport sharedSupport] unregisterLocalService:service];
}

MMLuaReturn *_CallLuaFunction(NSLock *lock, lua_State *lua_state, char *scripts, NSString *luaFuncName, NSArray *params) {
    [lock lock];
    
    int errorHandler = 0;
#ifdef DEBUG
    lua_getglobal(lua_state, "debug");
    lua_getfield(lua_state, -1, "traceback");
    lua_remove(lua_state, -2);
    errorHandler = lua_gettop(lua_state);
#endif
    
    lua_getglobal(lua_state, [luaFuncName UTF8String]);
    
    _AttachCFunctions(lua_state);
    
    NSInteger parameterCount = [params count];
    
    for (NSString *tmpParameter in params) {
        NSString *filteredParameter = _FilterInputParameter(tmpParameter);
        lua_pushstring(lua_state, [filteredParameter UTF8String]);
    }
    
    int result = lua_pcall(lua_state, (int)parameterCount, 1, errorHandler);
    NSString *errorMsg = @"unknown error";
    if (result == 0) {
        const char *returnValue = lua_tostring(lua_state, -1);
        NSString *value = @"";
        if(returnValue){
            value = [NSString stringWithUTF8String:returnValue];
        }
        value = _RestoreOutputValue(value);
#ifdef DEBUG
        lua_pop(lua_state, 1);
#endif
        [lock unlock];
        
        return [MMLuaReturn returnWithValue:value];
    } else {
        if (result == LUA_YIELD) {
            errorMsg = @"lua yield";
        } else if(result == LUA_ERRRUN) {
            errorMsg = @"Runtime error";
        } else if(result == LUA_ERRSYNTAX) {
            errorMsg = @"Syntax error";
        } else if(result == LUA_ERRMEM) {
            errorMsg = @"lua errmem";
        } else if(result == LUA_ERRERR) {
            errorMsg = @"lua errerr";
        }
#ifdef DEBUG
        errorMsg = [NSString stringWithFormat:@"%@\n%s", errorMsg, lua_tostring(lua_state, -1)];
        NSLog(@"LUA ERROR: error found by calling function: <%@> {\n%@\n}", luaFuncName, errorMsg);
#else
        errorMsg = [NSString stringWithFormat:@"%@\n", errorMsg];
#endif
    }
#ifdef DEBUG
    lua_pop(lua_state, 1);
#endif
    [lock unlock];
    
    return [MMLuaReturn returnWithError:errorMsg];
}

@end
