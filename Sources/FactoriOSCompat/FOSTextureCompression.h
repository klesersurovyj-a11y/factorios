// CPU decoding of the BC (S3TC/RGTC) texture formats the game uses, for GPUs without them.
//
// Every Mac that runs the game's Metal renderer samples BC1-BC5 natively, so the game creates such textures
// unconditionally (ResourceManager's placeholders among them). Apple's iPhone GPUs report
// supportsBCTextureCompression NO and reject those formats, so the Metal fixes create the uncompressed format with the
// same channels instead and decode each upload with these functions.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/// The uncompressed format with the channels and encoding `format` decodes to: RGBA8 for BC1-BC3, R8 for BC4, RG8 for
/// BC5, sRGB and signed variants kept. MTLPixelFormatInvalid for every other format, BC6H and BC7 included.
MTLPixelFormat FOSBCDecodedFormat(MTLPixelFormat format);

/// Bytes per texel of `FOSBCDecodedFormat(format)`; 0 when that is MTLPixelFormatInvalid.
NSUInteger FOSBCDecodedBytesPerPixel(MTLPixelFormat format);

/// Bytes per 4×4 block: 8 for BC1 and BC4, 16 for BC2, BC3 and BC5; 0 for formats the decoder doesn't handle.
NSUInteger FOSBCBlockBytes(MTLPixelFormat format);

/// Decodes a `width`×`height` texel image of `format` (one of the formats FOSBCDecodedFormat handles).
///
/// - Parameters:
///   - source: The first block row; rows of blocks are `sourceBytesPerRow` apart, and a partial block at the right or
///     bottom edge holds texels past `width` or `height` that are skipped.
///   - destination: The first texel row of `FOSBCDecodedFormat(format)`; rows are `destinationBytesPerRow` apart.
void FOSBCDecode(MTLPixelFormat format, const uint8_t *source, NSUInteger sourceBytesPerRow, NSUInteger width,
                 NSUInteger height, uint8_t *destination, NSUInteger destinationBytesPerRow);

NS_ASSUME_NONNULL_END
