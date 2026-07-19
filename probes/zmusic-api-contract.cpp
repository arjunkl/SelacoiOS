#include <zmusic.h>

#include <cstddef>
#include <cstdint>

namespace {
void message_callback(int, const char *) {}
const char *nice_path(const char *path) { return path; }
const char *soundfont_path(const char *, int) { return nullptr; }
void *open_soundfont(const char *, int) { return nullptr; }
ZMusicCustomReader *open_soundfont_file(void *, const char *) { return nullptr; }
void add_soundfont_path(void *, const char *) {}
void close_soundfont(void *) {}
}

int SelacoZMusicAPIContract(void)
{
    ZMusicCallbacks callbacks{};
    callbacks.MessageFunc = message_callback;
    callbacks.NicePath = nice_path;
    callbacks.PathForSoundfont = soundfont_path;
    callbacks.OpenSoundFont = open_soundfont;
    callbacks.SF_OpenFile = open_soundfont_file;
    callbacks.SF_AddToSearchPath = add_soundfont_path;
    callbacks.SF_Close = close_soundfont;

    ZMusic_SetCallbacks(&callbacks);
    ZMusic_SetGenMidi(nullptr);
    ZMusic_SetWgOpn(nullptr, 0);
    ZMusic_SetDmxGus(nullptr, 0);

    uint32_t header[8]{};
    const EMIDIType type = ZMusic_IdentifyMIDIType(header, sizeof(header));
    ZMusic_MidiSource source = ZMusic_CreateMIDISource(
        reinterpret_cast<const uint8_t *>(header), sizeof(header), type);

    ZMusic_MusicStream stream = ZMusic_OpenSongMem(
        header, sizeof(header), MDEV_DEFAULT, nullptr);
    if (stream != nullptr) {
        ZMusic_VolumeChanged(stream);
        (void)ZMusic_GetStats(stream);
        ZMusic_Close(stream);
    }

    (void)source;
    (void)ZMusic_GetLastError();
    return static_cast<int>(zmusic_snd_musicvolume) +
        static_cast<int>(zmusic_relative_volume);
}
