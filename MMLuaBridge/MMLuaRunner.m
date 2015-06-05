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

NSString *_StringByRestoringEscapedString(NSString *string);
NSString *_StringByEscapingUnicode(NSString *string);

NSString *MMLuaRecognizableString(NSString *string)
{
    return _StringByEscapingUnicode(string);
}

NSString *MMRestoreLuaRecognizableString(NSString *luaRecognizableString)
{
    return _StringByRestoringEscapedString(luaRecognizableString);
}

#pragma mark - MMLuaReturn
@interface MMLuaReturn ()

@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *error;

@end

@implementation MMLuaReturn

+ (instancetype)returnWithValue:(NSString *)value
{
    MMLuaReturn *ret = [MMLuaReturn new];
    ret.value = value;
    
    return ret;
}

+ (instancetype)returnWithError:(NSString *)error
{
    MMLuaReturn *ret = [MMLuaReturn new];
    ret.error = error;
    
    return ret;
}

@end

BOOL _SingleCharIsChinese(NSString *str)
{
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
NSString *luaStringParam(lua_State *L, int location)
{
    const char *paramValue = lua_tostring(L, location);
    NSString *paramString = @"";
    if(paramValue){
        paramString = [NSString stringWithFormat:@"%s", paramValue];
    }
    paramString = _StringByRestoringEscapedString(paramString);
    if(paramString.length == 0){
        paramString = @"";
    }
    
    return paramString;
}

void pushString(lua_State *L, NSString *returnValue)
{
    returnValue = _StringByEscapingUnicode(returnValue);
    lua_pushstring(L, [returnValue UTF8String]);
}

int ustring_substring(lua_State *L)
{
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

int ustring_length(lua_State *L)
{
    NSString *string = luaStringParam(L, 1);
    lua_pushnumber(L, [string length]);
    
    return 1;
}

int ustring_find(lua_State *L)
{
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

int ustring_encodeURL(lua_State *L)
{
    NSString *str = luaStringParam(L, 1);
    if(str.length != 0){
        CFStringRef urlString = CFURLCreateStringByAddingPercentEscapes(NULL,(CFStringRef)str, NULL,(CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8);
        str = (__bridge NSString *)urlString;
        CFAutorelease(urlString);
    }
    pushString(L, str);
    
    return 1;
}

int ustring_replace(lua_State *L)
{
    NSString *string = luaStringParam(L, 1);
    NSString *occurrences = luaStringParam(L, 2);
    NSString *replacement = luaStringParam(L, 3);
    string = [string stringByReplacingOccurrencesOfString:occurrences withString:replacement];
    pushString(L, string);
    
    return 1;
}


#pragma mark - Interaction Utils
static char *CustomHexList = "0123456789abcdef";

char _CustomHexCharForByte(unsigned char c)
{
    return *(CustomHexList + c);
}

unsigned char _ByteForCustomHexChar(char c)
{
    size_t len = strlen(CustomHexList);
    for(int i = 0; i < len; ++i){
        if(c == *(CustomHexList + i)){
            return i;
        }
    }
    
    return 0;
}

NSString *_HexStringByEncodingData(NSData *data)
{
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

NSString *_EncodeUnichar(unichar unich)
{
    unsigned char low = unich & 0xFF;
    unsigned char high = ((unich & 0xFF00) >> 8);
    unsigned char bytes[] = {low, high};
    NSData *data = [NSData dataWithBytes:bytes length:2];
    NSString *str = _HexStringByEncodingData(data);
    
    return str;
}

NSString *_HexStringByEncodingString(NSString *string)
{
    if([string isEqualToString:@""]){
        return @"";
    }
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    
    return _HexStringByEncodingData(data);
}

NSData *_DataByDecodingHexString(NSString *string)
{
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

NSString *_RestoreUnichar(NSString *str)
{
    NSData *data = _DataByDecodingHexString(str);
    unsigned char bytes[2];
    [data getBytes:bytes length:2];
    unichar unich = bytes[0] + (bytes[1] << 8);
    unichar unichars[1] = {unich};
    
    return [NSString stringWithCharacters:unichars length:1];
}

NSString *_StringByEscapingUnicode(NSString *string)
{
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

NSString *_StringByRestoringEscapedString(NSString *string)
{
    if(string.length == 0){
        return @"";
    }
    NSMutableString *allString = [NSMutableString string];
    NSRange beginRange;
    NSRange endRange = NSMakeRange(0, string.length);
    while(true){
        beginRange = [string rangeOfString:@"[u]" options:NSCaseInsensitiveSearch range:endRange];
        if(beginRange.location == NSNotFound){
            if(endRange.location == 0){
                [allString appendString:string];
            }else if(endRange.location != string.length){
                [allString appendString:[string substringFromIndex:endRange.location]];
            }
            break;
        }
        NSString *en = [string substringWithRange:NSMakeRange(endRange.location, beginRange.location - endRange.location)];
        [allString appendString:en];
        beginRange.location += 3;
        beginRange.length = string.length - beginRange.location;
        endRange = [string rangeOfString:@"[/u]" options:NSCaseInsensitiveSearch range:beginRange];
        NSString *cn = [string substringWithRange:NSMakeRange(beginRange.location, endRange.location - beginRange.location)];
        cn = _RestoreUnichar(cn);
        [allString appendString:cn];
        endRange.location += 4;
        endRange.length = string.length - endRange.location;
    }
    
    return allString;
}

NSString *_FilterInputParameter(NSString *parameter)
{
    if(_StringContainsChinese(parameter)){
        parameter = _StringByEscapingUnicode(parameter);
    }
    
    return parameter;
}

NSString *_RestoreOutputValue(NSString *returnValue)
{
    return _StringByRestoringEscapedString(returnValue);
}

void _PushFunctionToLua(lua_State *L, char *functionName, int (*func)(lua_State *L))
{
    lua_pushstring(L, functionName);
    lua_pushcfunction(L, func);
    lua_settable(L, LUA_GLOBALSINDEX);
}

void _AttachCFunctions(lua_State *L)
{
    _PushFunctionToLua(L, "ustr_find", ustring_find); // ustr_find(from_str, target_str, begin_index, reverse)
    _PushFunctionToLua(L, "ustr_len", ustring_length);// ustr_len(str)
    _PushFunctionToLua(L, "ustr_sub", ustring_substring);// ustr_substr(begin_index, end_index)
    _PushFunctionToLua(L, "ustr_encode", ustring_encodeURL);// ustr_encodeURL(str)
    _PushFunctionToLua(L, "ustr_rep", ustring_replace);// ustr_replace(str, target_str, replacement_str)
}

#pragma mark - MMLuaBridge
@interface MMLuaRunner () {
    char *_script;
    lua_State *_lua_state;
}

@end

@implementation MMLuaRunner

- (void)dealloc
{
    if(_lua_state){
        lua_close(_lua_state);
    }
    
    if (_script) {
        free(_script);
    }
}



- (id)initWithScripts:(NSString *)scripts
{
    self = [super init];
    
    NSAssert(scripts.length != 0, @"Scripts cannot be NULL");
    _script = malloc(sizeof(char *) * (scripts.length + 1));
    strcpy(_script, [scripts UTF8String]);

    [self _initLuaState];
    
    return self;
}

- (void)_initLuaState
{
    if(_lua_state){
        lua_close(_lua_state);
    }
    _lua_state = lua_open();
    luaL_openlibs(_lua_state);
    
    if(luaL_dostring(_lua_state, _script)){
        // dostring error, lua cannot do this script
        const char *error = lua_tostring(_lua_state, -1);
        NSLog(@"Failed to init lua_state, \nerror message:%s", error);
    }
}

- (MMLuaReturn *)runFunction:(NSString *)name parameters:(NSString *)firstParameter, ... NS_REQUIRES_NIL_TERMINATION
{
    va_list args;
    NSMutableArray *parameters = [NSMutableArray array];
    if(firstParameter){
        va_start(args, firstParameter);
        for(NSString *tmpParameter = firstParameter; tmpParameter; tmpParameter = va_arg(args, id)){
            [parameters addObject:tmpParameter];
        }
        va_end(args);
    }
    
    return _CallLua(_lua_state, _script, name, parameters);
}

MMLuaReturn *_CallLua(lua_State *lua_state, char *scripts, NSString *luaFuncName, NSArray *params)
{
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
        NSLog(@"Error found by running function:<%@>, \nerror message:%@", luaFuncName, errorMsg);
#else
        errorMsg = [NSString stringWithFormat:@"%@\n", errorMsg];
#endif
    }
#ifdef DEBUG
    lua_pop(lua_state, 1);
#endif
    return [MMLuaReturn returnWithError:errorMsg];
}

@end
