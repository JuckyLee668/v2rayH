#include "napi/native_api.h"
#include "libxray.h"

#define XRAY_CORE_VERSION "v1.261029.0"
#define SINGBOX_CORE_VERSION "sing-box v1.14.4"

static char *CopyStringArg(napi_env env, napi_value value)
{
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    char *buf = new char[len + 1];
    napi_get_value_string_utf8(env, value, buf, len + 1, &len);
    return buf;
}

static napi_value NativeStartXray(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char *buf = CopyStringArg(env, args[0]);

    int result = StartXray(buf);
    delete[] buf;

    napi_value ret;
    napi_create_int32(env, result, &ret);
    return ret;
}

static napi_value NativeStopXray(napi_env env, napi_callback_info info)
{
    int result = StopXray();

    napi_value ret;
    napi_create_int32(env, result, &ret);
    return ret;
}

static napi_value NativeIsXrayRunning(napi_env env, napi_callback_info info)
{
    int result = IsXrayRunning();

    napi_value ret;
    napi_create_int32(env, result, &ret);
    return ret;
}

static napi_value NativeGetLastError(napi_env env, napi_callback_info info)
{
    char *msg = GetLastError();

    napi_value ret;
    napi_create_string_utf8(env, msg != nullptr ? msg : "", NAPI_AUTO_LENGTH, &ret);
    return ret;
}

static napi_value NativeGetCoreVersion(napi_env env, napi_callback_info info)
{
    napi_value ret;
    napi_create_string_utf8(env, XRAY_CORE_VERSION, NAPI_AUTO_LENGTH, &ret);
    return ret;
}

static napi_value NativeStartVpnTun(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = { nullptr, nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t fd = 0;
    napi_get_value_int32(env, args[0], &fd);

    char *cfg = CopyStringArg(env, args[1]);
    char *assets = CopyStringArg(env, args[2]);

    int result = StartVpnTun((int)fd, cfg, assets);
    delete[] cfg;
    delete[] assets;

    napi_value ret;
    napi_create_int32(env, result, &ret);
    return ret;
}

static napi_value NativeStopVpn(napi_env env, napi_callback_info info)
{
    int result = StopVpn();

    napi_value ret;
    napi_create_int32(env, result, &ret);
    return ret;
}

static napi_value NativeStartSingbox(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char *buf = CopyStringArg(env, args[0]);

    int result = StartSingbox(buf);
    delete[] buf;

    napi_value ret;
    napi_create_int32(env, result, &ret);
    return ret;
}

static napi_value NativeStopSingbox(napi_env env, napi_callback_info info)
{
    int result = StopSingbox();

    napi_value ret;
    napi_create_int32(env, result, &ret);
    return ret;
}

static napi_value NativeIsSingboxRunning(napi_env env, napi_callback_info info)
{
    int result = IsSingboxRunning();

    napi_value ret;
    napi_create_int32(env, result, &ret);
    return ret;
}

static napi_value NativeGetSingboxVersion(napi_env env, napi_callback_info info)
{
    napi_value ret;
    napi_create_string_utf8(env, SINGBOX_CORE_VERSION, NAPI_AUTO_LENGTH, &ret);
    return ret;
}

static napi_value NativeGetSingboxError(napi_env env, napi_callback_info info)
{
    char *msg = GetSingboxError();

    napi_value ret;
    napi_create_string_utf8(env, msg != nullptr ? msg : "", NAPI_AUTO_LENGTH, &ret);
    return ret;
}

struct DelayWork {
    napi_async_work work;
    napi_deferred deferred;
    char *cfg;
    char *singboxCfg;
    char *url;
    int64_t result;
};

static void DelayExecute(napi_env env, void *data)
{
    DelayWork *w = static_cast<DelayWork *>(data);
    w->result = MeasureDelay(w->cfg, w->singboxCfg, w->url);
}

static void DelayComplete(napi_env env, napi_status status, void *data)
{
    DelayWork *w = static_cast<DelayWork *>(data);
    napi_value result;
    napi_create_int64(env, w->result, &result);
    napi_resolve_deferred(env, w->deferred, result);
    napi_delete_async_work(env, w->work);
    delete[] w->cfg;
    delete[] w->singboxCfg;
    delete[] w->url;
    delete w;
}

static napi_value NativeMeasureDelay(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = { nullptr, nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char *cfg = CopyStringArg(env, args[0]);
    char *singboxCfg = CopyStringArg(env, args[1]);
    char *url = CopyStringArg(env, args[2]);

    DelayWork *w = new DelayWork();
    w->cfg = cfg;
    w->singboxCfg = singboxCfg;
    w->url = url;
    w->result = -1;

    napi_value promise;
    napi_create_promise(env, &w->deferred, &promise);

    napi_value resourceName;
    napi_create_string_utf8(env, "MeasureDelay", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, DelayExecute, DelayComplete, w, &w->work);
    napi_queue_async_work(env, w->work);

    return promise;
}

struct DownloadWork {
    napi_async_work work;
    napi_deferred deferred;
    char *cfg;
    char *singboxCfg;
    char *url;
    int64_t maxBytes;
    double result;
};

static void DownloadExecute(napi_env env, void *data)
{
    DownloadWork *w = static_cast<DownloadWork *>(data);
    w->result = MeasureDownload(w->cfg, w->singboxCfg, w->url, w->maxBytes);
}

static void DownloadComplete(napi_env env, napi_status status, void *data)
{
    DownloadWork *w = static_cast<DownloadWork *>(data);
    napi_value result;
    napi_create_double(env, w->result, &result);
    napi_resolve_deferred(env, w->deferred, result);
    napi_delete_async_work(env, w->work);
    delete[] w->cfg;
    delete[] w->singboxCfg;
    delete[] w->url;
    delete w;
}

static napi_value NativeMeasureDownload(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = { nullptr, nullptr, nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char *cfg = CopyStringArg(env, args[0]);
    char *singboxCfg = CopyStringArg(env, args[1]);
    char *url = CopyStringArg(env, args[2]);

    int64_t maxBytes = 0;
    napi_get_value_int64(env, args[3], &maxBytes);

    DownloadWork *w = new DownloadWork();
    w->cfg = cfg;
    w->singboxCfg = singboxCfg;
    w->url = url;
    w->maxBytes = maxBytes;
    w->result = -1;

    napi_value promise;
    napi_create_promise(env, &w->deferred, &promise);

    napi_value resourceName;
    napi_create_string_utf8(env, "MeasureDownload", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, DownloadExecute, DownloadComplete, w, &w->work);
    napi_queue_async_work(env, w->work);

    return promise;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "startXray", nullptr, NativeStartXray, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopXray", nullptr, NativeStopXray, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isXrayRunning", nullptr, NativeIsXrayRunning, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getLastError", nullptr, NativeGetLastError, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getCoreVersion", nullptr, NativeGetCoreVersion, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startVpnTun", nullptr, NativeStartVpnTun, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopVpn", nullptr, NativeStopVpn, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "measureDelay", nullptr, NativeMeasureDelay, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "measureDownload", nullptr, NativeMeasureDownload, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startSingbox", nullptr, NativeStartSingbox, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopSingbox", nullptr, NativeStopSingbox, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isSingboxRunning", nullptr, NativeIsSingboxRunning, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getSingboxVersion", nullptr, NativeGetSingboxVersion, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getSingboxError", nullptr, NativeGetSingboxError, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module entryModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&entryModule);
}
