#import "FOSTextureCompression.h"

// Block layouts follow Microsoft's BC1-BC5 specification ("Texture Block Compression in Direct3D 11"): little-endian
// fields, texels in row-major order inside the 4×4 block, index i in the low bits first.

/// Texels per block edge and per block.
static const NSUInteger FOSBlockEdge = 4;
static const NSUInteger FOSBlockTexels = 16;

static uint16_t FOSRead16(const uint8_t *bytes) {
    return (uint16_t)((unsigned)bytes[0] | ((unsigned)bytes[1] << 8U));
}

static uint64_t FOSRead64(const uint8_t *bytes) {
    uint64_t value = 0;
    for (NSUInteger index = 8; index > 0; index--) {
        value = (value << 8U) | bytes[index - 1];
    }
    return value;
}

/// Rounds `numerator / denominator` to the nearest integer, both non-negative.
static int FOSRoundedDivide(int numerator, int denominator) {
    return (numerator + (denominator / 2)) / denominator;
}

/// Rounds a signed `numerator / denominator` to the nearest integer, halves away from zero.
static int FOSRoundedDivideSigned(int numerator, int denominator) {
    if (numerator < 0) {
        return -FOSRoundedDivide(-numerator, denominator);
    }
    return FOSRoundedDivide(numerator, denominator);
}

#pragma mark - Colour blocks (BC1, and the colour half of BC2 and BC3)

/// RGB565 widened to 8 bits per channel by repeating each channel's high bits.
static void FOSExpand565(uint16_t color, uint8_t rgba[4]) {
    unsigned red = ((unsigned)color >> 11U) & 31U;
    unsigned green = ((unsigned)color >> 5U) & 63U;
    unsigned blue = (unsigned)color & 31U;
    rgba[0] = (uint8_t)((red << 3U) | (red >> 2U));
    rgba[1] = (uint8_t)((green << 2U) | (green >> 4U));
    rgba[2] = (uint8_t)((blue << 3U) | (blue >> 2U));
    rgba[3] = 255;
}

/// Writes the colour block's 16 texels as RGBA. BC1 picks three colours plus transparent black when the first endpoint
/// isn't greater than the second; BC2 and BC3 (`fourColors`) always interpolate four colours.
///
/// The thirds use 43/64 and 21/64 rounded down after adding 32, the weights Apple GPUs decode with (measured against a
/// Mac's GPU), so an emulated texture holds the colours a Mac shows.
static void FOSDecodeColorBlock(const uint8_t *block, BOOL fourColors, uint8_t texels[16][4]) {
    uint16_t first = FOSRead16(block);
    uint16_t second = FOSRead16(block + 2);
    uint8_t palette[4][4];
    FOSExpand565(first, palette[0]);
    FOSExpand565(second, palette[1]);
    BOOL interpolateTwo = fourColors;
    if (first > second) {
        interpolateTwo = YES;
    }
    for (NSUInteger channel = 0; channel < 3; channel++) {
        unsigned start = palette[0][channel];
        unsigned end = palette[1][channel];
        if (interpolateTwo) {
            palette[2][channel] = (uint8_t)(((43U * start) + (21U * end) + 32U) >> 6U);
            palette[3][channel] = (uint8_t)(((21U * start) + (43U * end) + 32U) >> 6U);
        } else {
            palette[2][channel] = (uint8_t)((start + end + 1U) >> 1U);
            palette[3][channel] = 0;
        }
    }
    palette[2][3] = 255;
    palette[3][3] = interpolateTwo ? 255 : 0;
    uint32_t indices = (uint32_t)FOSRead16(block + 4) | ((uint32_t)FOSRead16(block + 6) << 16U);
    for (NSUInteger texel = 0; texel < FOSBlockTexels; texel++) {
        memcpy(texels[texel], palette[(indices >> (2 * texel)) & 3U], 4);
    }
}

#pragma mark - Single-channel blocks (BC3 alpha, BC4, BC5)

/// Weights of the second endpoint, in 64ths, for the values between the endpoints: Apple GPUs' sevenths (when the
/// first endpoint is greater) and fifths, measured against a Mac's GPU.
static const int FOSSevenths[6] = {9, 18, 27, 37, 46, 55};
static const int FOSFifths[4] = {13, 26, 38, 51};

/// The eight values of an interpolated single-channel block, rounded to the nearest integer. With the first endpoint
/// greater, six values lie between the endpoints; otherwise four do, followed by the channel's minimum and maximum.
static void FOSChannelPalette(int first, int second, int minimum, int maximum, int palette[8]) {
    palette[0] = first;
    palette[1] = second;
    if (first > second) {
        for (NSUInteger step = 0; step < 6; step++) {
            int weight = FOSSevenths[step];
            palette[step + 2] = FOSRoundedDivideSigned(((64 - weight) * first) + (weight * second), 64);
        }
        return;
    }
    for (NSUInteger step = 0; step < 4; step++) {
        int weight = FOSFifths[step];
        palette[step + 2] = FOSRoundedDivideSigned(((64 - weight) * first) + (weight * second), 64);
    }
    palette[6] = minimum;
    palette[7] = maximum;
}

/// Writes the 16 values of an interpolated single-channel block, `stride` bytes apart. Signed blocks hold
/// two's-complement endpoints, with -128 read as -127, as the signed-normalized formats define.
static void FOSDecodeChannelBlock(const uint8_t *block, BOOL isSigned, uint8_t *texels, NSUInteger stride) {
    int palette[8];
    if (isSigned) {
        int first = (int8_t)block[0] < -127 ? -127 : (int8_t)block[0];
        int second = (int8_t)block[1] < -127 ? -127 : (int8_t)block[1];
        FOSChannelPalette(first, second, -127, 127, palette);
    } else {
        FOSChannelPalette(block[0], block[1], 0, 255, palette);
    }
    uint64_t indices = FOSRead64(block) >> 16U;
    for (NSUInteger texel = 0; texel < FOSBlockTexels; texel++) {
        texels[texel * stride] = (uint8_t)palette[(indices >> (3 * texel)) & 7U];
    }
}

/// BC2's alpha: 4 bits per texel, widened to 8 bits.
static void FOSDecodeExplicitAlpha(const uint8_t *block, uint8_t texels[16][4]) {
    uint64_t alphas = FOSRead64(block);
    for (NSUInteger texel = 0; texel < FOSBlockTexels; texel++) {
        texels[texel][3] = (uint8_t)(((alphas >> (4 * texel)) & 15U) * 17U);
    }
}

#pragma mark - Formats

typedef NS_ENUM(NSUInteger, FOSBlockKind) {
    FOSBlockKindNone,
    FOSBlockKindBC1,
    FOSBlockKindBC2,
    FOSBlockKindBC3,
    FOSBlockKindBC4,
    FOSBlockKindBC5,
};

static FOSBlockKind FOSKind(MTLPixelFormat format) {
    // Over the integer value: only the BC formats matter, and -Wswitch-enum would want every pixel format listed.
    switch ((NSUInteger)format) {
    case MTLPixelFormatBC1_RGBA:
    case MTLPixelFormatBC1_RGBA_sRGB:
        return FOSBlockKindBC1;
    case MTLPixelFormatBC2_RGBA:
    case MTLPixelFormatBC2_RGBA_sRGB:
        return FOSBlockKindBC2;
    case MTLPixelFormatBC3_RGBA:
    case MTLPixelFormatBC3_RGBA_sRGB:
        return FOSBlockKindBC3;
    case MTLPixelFormatBC4_RUnorm:
    case MTLPixelFormatBC4_RSnorm:
        return FOSBlockKindBC4;
    case MTLPixelFormatBC5_RGUnorm:
    case MTLPixelFormatBC5_RGSnorm:
        return FOSBlockKindBC5;
    default:
        return FOSBlockKindNone;
    }
}

static BOOL FOSIsSigned(MTLPixelFormat format) {
    switch ((NSUInteger)format) {
    case MTLPixelFormatBC4_RSnorm:
    case MTLPixelFormatBC5_RGSnorm:
        return YES;
    default:
        return NO;
    }
}

static BOOL FOSIsSRGB(MTLPixelFormat format) {
    switch ((NSUInteger)format) {
    case MTLPixelFormatBC1_RGBA_sRGB:
    case MTLPixelFormatBC2_RGBA_sRGB:
    case MTLPixelFormatBC3_RGBA_sRGB:
        return YES;
    default:
        return NO;
    }
}

MTLPixelFormat FOSBCDecodedFormat(MTLPixelFormat format) {
    switch (FOSKind(format)) {
    case FOSBlockKindBC1:
    case FOSBlockKindBC2:
    case FOSBlockKindBC3:
        return FOSIsSRGB(format) ? MTLPixelFormatRGBA8Unorm_sRGB : MTLPixelFormatRGBA8Unorm;
    case FOSBlockKindBC4:
        return FOSIsSigned(format) ? MTLPixelFormatR8Snorm : MTLPixelFormatR8Unorm;
    case FOSBlockKindBC5:
        return FOSIsSigned(format) ? MTLPixelFormatRG8Snorm : MTLPixelFormatRG8Unorm;
    case FOSBlockKindNone:
        return MTLPixelFormatInvalid;
    }
}

NSUInteger FOSBCDecodedBytesPerPixel(MTLPixelFormat format) {
    switch (FOSKind(format)) {
    case FOSBlockKindBC1:
    case FOSBlockKindBC2:
    case FOSBlockKindBC3:
        return 4;
    case FOSBlockKindBC4:
        return 1;
    case FOSBlockKindBC5:
        return 2;
    case FOSBlockKindNone:
        return 0;
    }
}

NSUInteger FOSBCBlockBytes(MTLPixelFormat format) {
    switch (FOSKind(format)) {
    case FOSBlockKindBC1:
    case FOSBlockKindBC4:
        return 8;
    case FOSBlockKindBC2:
    case FOSBlockKindBC3:
    case FOSBlockKindBC5:
        return 16;
    case FOSBlockKindNone:
        return 0;
    }
}

/// Decodes one block into 16 texels of `bytesPerPixel` bytes each, row-major.
static void FOSDecodeBlock(FOSBlockKind kind, BOOL isSigned, const uint8_t *block, uint8_t *texels) {
    uint8_t(*rgba)[4] = (uint8_t(*)[4])texels;
    switch (kind) {
    case FOSBlockKindBC1:
        FOSDecodeColorBlock(block, NO, rgba);
        break;
    case FOSBlockKindBC2:
        FOSDecodeColorBlock(block + 8, YES, rgba);
        FOSDecodeExplicitAlpha(block, rgba);
        break;
    case FOSBlockKindBC3:
        FOSDecodeColorBlock(block + 8, YES, rgba);
        FOSDecodeChannelBlock(block, NO, texels + 3, 4);
        break;
    case FOSBlockKindBC4:
        FOSDecodeChannelBlock(block, isSigned, texels, 1);
        break;
    case FOSBlockKindBC5:
        FOSDecodeChannelBlock(block, isSigned, texels, 2);
        FOSDecodeChannelBlock(block + 8, isSigned, texels + 1, 2);
        break;
    case FOSBlockKindNone:
        break;
    }
}

void FOSBCDecode(MTLPixelFormat format, const uint8_t *source, NSUInteger sourceBytesPerRow, NSUInteger width,
                 NSUInteger height, uint8_t *destination, NSUInteger destinationBytesPerRow) {
    FOSBlockKind kind = FOSKind(format);
    NSUInteger blockBytes = FOSBCBlockBytes(format);
    NSUInteger pixelBytes = FOSBCDecodedBytesPerPixel(format);
    BOOL isSigned = FOSIsSigned(format);
    uint8_t texels[16 * 4];
    for (NSUInteger blockY = 0; blockY * FOSBlockEdge < height; blockY++) {
        const uint8_t *blockRow = source + (blockY * sourceBytesPerRow);
        for (NSUInteger blockX = 0; blockX * FOSBlockEdge < width; blockX++) {
            FOSDecodeBlock(kind, isSigned, blockRow + (blockX * blockBytes), texels);
            NSUInteger x = blockX * FOSBlockEdge;
            NSUInteger columns = width - x < FOSBlockEdge ? width - x : FOSBlockEdge;
            for (NSUInteger row = 0; row < FOSBlockEdge && (blockY * FOSBlockEdge) + row < height; row++) {
                uint8_t *target = destination + (((blockY * FOSBlockEdge) + row) * destinationBytesPerRow) +
                                  (x * pixelBytes);
                memcpy(target, texels + (row * FOSBlockEdge * pixelBytes), columns * pixelBytes);
            }
        }
    }
}
