cmake_minimum_required(VERSION 3.16)
project(MultimediaSDKSmokeTest C)

set(CMAKE_C_STANDARD 11)

find_package(MultimediaSDK REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GLIB REQUIRED glib-2.0)

add_executable(smoke_test main.c)
target_link_libraries(smoke_test
    MultimediaSDK::gstreamer
    MultimediaSDK::gstvideo
    MultimediaSDK::gstapp
    MultimediaSDK::gstrtp
    ${GLIB_LIBRARIES}
)
target_include_directories(smoke_test PRIVATE ${GLIB_INCLUDE_DIRS})
