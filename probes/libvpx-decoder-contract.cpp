#include <vpx/vp8dx.h>
#include <vpx/vpx_codec.h>
#include <vpx/vpx_decoder.h>

#include <cstdint>
#include <cstring>

namespace {
int exercise_decoder(vpx_codec_iface_t *interface)
{
    if (interface == nullptr) {
        return 10;
    }

    vpx_codec_ctx_t context{};
    vpx_codec_dec_cfg_t configuration{};
    configuration.threads = 2;

    const vpx_codec_err_t initialization =
        vpx_codec_dec_init(&context, interface, &configuration, 0);
    if (initialization != VPX_CODEC_OK) {
        return 20 + static_cast<int>(initialization);
    }

    vpx_codec_stream_info_t stream_info{};
    stream_info.sz = sizeof(stream_info);
    (void)vpx_codec_get_stream_info(&context, &stream_info);

    const std::uint8_t empty_packet[1] = {0};
    (void)vpx_codec_decode(&context, empty_packet, 0, nullptr, 0);

    vpx_codec_iter_t iterator = nullptr;
    (void)vpx_codec_get_frame(&context, &iterator);
    (void)vpx_codec_error(&context);
    (void)vpx_codec_error_detail(&context);

    const vpx_codec_err_t destruction = vpx_codec_destroy(&context);
    return destruction == VPX_CODEC_OK ? 0 : 40 + static_cast<int>(destruction);
}
} // namespace

int main()
{
    const char *version = vpx_codec_version_str();
    if (version == nullptr || std::strstr(version, "v1.12.0") == nullptr) {
        return 1;
    }

    const int vp8_result = exercise_decoder(vpx_codec_vp8_dx());
    if (vp8_result != 0) {
        return vp8_result;
    }

    return exercise_decoder(vpx_codec_vp9_dx());
}
