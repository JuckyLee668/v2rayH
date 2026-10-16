cmake_minimum_required(VERSION 3.5.0)
project(entry)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/thirdparty/libxray/include)

add_library(entry SHARED napi_init.cpp)

add_library(xray STATIC IMPORTED)
set_target_properties(xray PROPERTIES
    IMPORTED_LOCATION ${NATIVERENDER_ROOT_PATH}/thirdparty/libxray/libs/${OHOS_ARCH}/libxray.a)

target_link_libraries(entry PUBLIC libace_napi.z.so libhilog_ndk.z.so xray)
