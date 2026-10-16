# 荒野手册 Android NDK 编译
#
# 此文件会被 build_apk.sh 复制到 <build>/android-build/app/CMakeLists.txt,
# 然后被 AGP 通过 cmake.path = file("CMakeLists.txt") 引用.
# 复制后位置: <build>/android-build/app/
#
# 目标: 项目根 CMakeLists.txt, 位于 <APP_DIR>/CMakeLists.txt
# 例如容器内 /project/CMakeLists.txt

# ----------------------------------------------------------------------------
# 1. 顶层声明: cmake_minimum_required + project()
# 原因: AGP 用 cmake -H<android-build/app> 跑 configure, 这里的 CMakeLists.txt
#       是 AGP 视角的 top-level. 没有 project()/cmake_minimum_required() 会
#       触发 warning: "No project() command is present".
#       名字与根项目不同 (OutdoorSurvival_AndroidBuild) 避免根 add_subdirectory
#       后重复 project() 警告. LANGUAGES CXX 与根项目一致.
# ----------------------------------------------------------------------------
cmake_minimum_required(VERSION 3.22)
project(OutdoorSurvival_AndroidBuild LANGUAGES CXX)

# ----------------------------------------------------------------------------
# 2. 让 find_package(Qt6) 在 Android NDK 工具链下能找到 Qt
# 原因: build_apk.sh 第 133 行 export QT_HOST_PATH=/opt/Qt/6.7.2/gcc_64,
#       gradle 子进程会继承这个环境变量. 但 AGP 跑 cmake configure 时
#       CMAKE_PREFIX_PATH 默认是空的, 找不到 Qt 6.7.2 android_arm64_v8a.
#
# Qt 6 找 component (Qt6Core/Quick/...) 的方式: 从 Qt6Config.cmake 自身路径
# 反推 install prefix = <prefix>/lib/cmake, 然后在此 prefix 下找 <comp>Config.
# 所以 CMAKE_PREFIX_PATH 必须包含 Qt 根目录 (如 /opt/Qt/6.7.2/android_arm64_v8a),
# 而不是 <prefix>/lib/cmake 或更深的路径.
#
# 同时设 Qt6_DIR 直接指向 Qt6Config.cmake 目录, 绕过 prefix 反推.
# ----------------------------------------------------------------------------
if(DEFINED ENV{QT_HOST_PATH})
    set(_QT_HOST_PATH "$ENV{QT_HOST_PATH}")
else()
    set(_QT_HOST_PATH "/opt/Qt/6.7.2/gcc_64")
endif()
# CMAKE_PREFIX_PATH 加 Qt 根 (不是 lib/cmake 子目录!)
list(APPEND CMAKE_PREFIX_PATH
    "${_QT_HOST_PATH}/../android_arm64_v8a"
    "${_QT_HOST_PATH}/../android_armv7"
    "${_QT_HOST_PATH}/../android_x86_64")
# Qt6_DIR 直接指向 lib/cmake/Qt6, 显式告诉 find_package(Qt6) 用哪个 Qt6Config.cmake
set(Qt6_DIR "${_QT_HOST_PATH}/../android_arm64_v8a/lib/cmake/Qt6"
    CACHE PATH "Qt6Config.cmake 位置" FORCE)
# 关键: NDK 工具链默认 CMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY,
# find_package(Qt6) 即使 CMAKE_PREFIX_PATH 包含 Qt 路径也找不到 Qt6Core 等 component.
# 改为 BOTH 允许在 ROOT_PATH 外找. 不会影响 NDK 工具链对 include/library 的
# 限制 (CMAKE_FIND_ROOT_PATH_MODE_INCLUDE/LIBRARY/EXECUTE/PROGRAM 仍默认 ONLY).
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
unset(_QT_HOST_PATH)

# ----------------------------------------------------------------------------
# 3. 探查项目根 (1-4 级父目录), 用 set() 不要用 file(GLOB)
# file(GLOB) 不会展开 ${...} 变量, 会把整个字符串当字面量去 glob, 永远找不到.
# ----------------------------------------------------------------------------
set(_ROOT_CANDIDATES
    "${CMAKE_CURRENT_LIST_DIR}/../../../.."
    "${CMAKE_CURRENT_LIST_DIR}/../../.."
    "${CMAKE_CURRENT_LIST_DIR}/../.."
    "${CMAKE_CURRENT_LIST_DIR}/..")
set(_APP_ROOT "")
foreach(_cand IN LISTS _ROOT_CANDIDATES)
    if(IS_DIRECTORY "${_cand}" AND EXISTS "${_cand}/CMakeLists.txt")
        set(_APP_ROOT "${_cand}")
        break()
    endif()
endforeach()
if(NOT _APP_ROOT)
    message(FATAL_ERROR
        "android/app/CMakeLists.txt: 无法定位项目根. 已检查: ${_ROOT_CANDIDATES}")
endif()
message(STATUS "[android/app/CMakeLists.txt] 项目根: ${_APP_ROOT}")

# 编译 Qt 应用
add_subdirectory(${_APP_ROOT} ${CMAKE_BINARY_DIR}/outdoor-survival-build)
unset(_APP_ROOT)
unset(_ROOT_CANDIDATES)
unset(_cand)

# 安装 Qt 部署的 .so 文件
install(DIRECTORY "${CMAKE_BINARY_DIR}/lib/"
        DESTINATION "lib"
        OPTIONAL)

# 复制可执行文件
install(TARGETS OutdoorSurvival
        RUNTIME DESTINATION "lib")
