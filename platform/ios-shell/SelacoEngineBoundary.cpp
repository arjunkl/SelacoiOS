#include "SelacoEngineBoundary.h"

#include "TSQueue.h"
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

bool SelacoIOSQueueSelfTest(void)
{
    TSQueue<int> queue;
    int input = 0x53454C41;
    int output = 0;
    queue.queue(input);
    return queue.dequeue(output) && output == input;
}
