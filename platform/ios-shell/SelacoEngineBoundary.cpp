#include "SelacoEngineBoundary.h"

#include <cstddef>
#include <cstring>

#include "superfasthash.h"
#include "version.h"

#define SELACOIOS_STRINGIFY_INNER(value) #value
#define SELACOIOS_STRINGIFY(value) SELACOIOS_STRINGIFY_INNER(value)

const char *SelacoIOSGameSignature(void)
{
    return GAMESIG;
}

const char *SelacoIOSEngineVersion(void)
{
    return "GZDoom " SELACOIOS_STRINGIFY(ENG_MAJOR) "." SELACOIOS_STRINGIFY(ENG_MINOR) "." SELACOIOS_STRINGIFY(ENG_REVISION);
}

int SelacoIOSEngineSelfTest(void)
{
    const char *mixed_case = "Selaco";
    const char *upper_case = "SELACO";
    const uint32_t first = SuperFastHashI(mixed_case, std::strlen(mixed_case));
    const uint32_t second = SuperFastHashI(upper_case, std::strlen(upper_case));
    return first != 0 && first == second;
}
