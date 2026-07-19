#include "SelacoEngineBoundary.h"

#include "TSQueue.h"
#include "version.h"

const char *SelacoIOSGameSignature(void)
{
    return GAMESIG;
}

const char *SelacoIOSEngineVersion(void)
{
    return "GZDoom " XSTR(ENG_MAJOR) "." XSTR(ENG_MINOR) "." XSTR(ENG_REVISION);
}

bool SelacoIOSQueueSelfTest(void)
{
    TSQueue<int> queue;
    int input = 0x53454C41;
    int output = 0;
    queue.queue(input);
    return queue.dequeue(output) && output == input;
}
