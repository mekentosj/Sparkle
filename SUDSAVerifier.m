//
//  SUDSAVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//
//  Includes code by Zach Waldowski on 10/18/13.
//  Copyright 2014 Big Nerd Ranch. Licensed under MIT.
//
//  Includes code from Plop by Mark Hamlin.
//  Copyright 2011 Mark Hamlin. Licensed under BSD.
//

#import "SUDSAVerifier.h"
#include <CommonCrypto/CommonDigest.h>

@implementation SUDSAVerifier {
	SecKeyRef _secKey;
}

+ (BOOL)validatePath:(NSString *)path withEncodedDSASignature:(NSString *)encodedSignature withPublicDSAKey:(NSString *)pkeyString
{
	if (!encodedSignature || !path) return NO;

	SUDSAVerifier *verifier = [[[self alloc] initWithPublicKeyString:pkeyString] autorelease];

	if (!verifier) return NO;

	NSString *strippedSignature = [encodedSignature stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSData *signature = [[[NSData alloc] initWithBase64Encoding:strippedSignature] autorelease];
	return [verifier verifyFileAtPath:path signature:signature];
}

- (instancetype)initWithPublicKeyString:(NSString *)string
{
	return [self initWithPublicKeyData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

- (instancetype)initWithPublicKeyData:(NSData *)data
{
	self = [super init];
	if (!self) return nil;
    if (!data.length) { [self release]; return nil; }

	SecExternalFormat format = kSecFormatOpenSSL;
	SecExternalItemType itemType = kSecItemTypePublicKey;
	SecItemImportExportKeyParameters params = {};
	CFArrayRef items = NULL;

	OSStatus status = SecItemImport((__bridge CFDataRef)data, NULL, &format, &itemType, 0, &params, NULL, &items);
	if (status || !items) {
		if (items) {
			CFRelease(items);
		}
		[self release];
		return nil;
	}

	if (format == kSecFormatOpenSSL && itemType == kSecItemTypePublicKey && CFArrayGetCount(items) == 1) {
		_secKey = (SecKeyRef)CFRetain(CFArrayGetValueAtIndex(items, 0));
	}

	CFRelease(items);

	return self;
}

- (void)dealloc
{
	if (_secKey) { CFRelease(_secKey); }
    [super dealloc];
}

- (BOOL)verifyURL:(NSURL *)URL signature:(NSData *)signature
{
	NSInputStream *dataInputStream = [NSInputStream inputStreamWithURL:URL];
	return [self verifyStream:dataInputStream signature:signature];
}

- (BOOL)verifyFileAtPath:(NSString *)path signature:(NSData *)signature
{
	if (!path.length) return NO;
	NSInputStream *dataInputStream = [NSInputStream inputStreamWithFileAtPath:path];
	return [self verifyStream:dataInputStream signature:signature];
}

- (BOOL)verifyStream:(NSInputStream *)stream signature:(NSData *)signature
{
	if (!stream || !signature) { return NO; }

	__block SecGroupTransformRef group = SecTransformCreateGroupTransform();
	__block SecTransformRef dataReadTransform = NULL;
	__block SecTransformRef dataDigestTransform = NULL;
	__block SecTransformRef dataVerifyTransform = NULL;
	__block CFErrorRef error = NULL;

	BOOL(^cleanup)(void) = ^{
		if (group) CFRelease(group);
		if (dataReadTransform) CFRelease(dataReadTransform);
		if (dataDigestTransform) CFRelease(dataDigestTransform);
		if (dataVerifyTransform) CFRelease(dataVerifyTransform);
		if (error) CFRelease(error);
		return NO;
	};

	dataReadTransform = SecTransformCreateReadTransformWithReadStream((__bridge CFReadStreamRef)stream);
	if (!dataReadTransform) { return cleanup(); }

	dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA1, CC_SHA1_DIGEST_LENGTH, NULL);
	if (!dataDigestTransform) { return cleanup(); }

	dataVerifyTransform = SecVerifyTransformCreate(_secKey, (__bridge CFDataRef)signature, NULL);
	if (!dataVerifyTransform) { return cleanup(); }

	SecTransformConnectTransforms(dataReadTransform, kSecTransformOutputAttributeName, dataDigestTransform, kSecTransformInputAttributeName, group, &error);
	if (error) { return cleanup(); }
	SecTransformConnectTransforms(dataDigestTransform, kSecTransformOutputAttributeName, dataVerifyTransform, kSecTransformInputAttributeName, group, &error);
	if (error) { return cleanup(); }

	NSNumber *result = CFBridgingRelease(SecTransformExecute(group, NULL));
	cleanup();
	return result.boolValue;
}

@end
