macro(cpprestsdk_find_boost_android_package)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  if(CMAKE_HOST_WIN32)
    set(WIN32 1)
    set(UNIX)
  elseif(CMAKE_HOST_APPLE)
    set(APPLE 1)
    set(UNIX)
  endif()
  find_package(${ARGN})
  set(APPLE)
  set(WIN32)
  set(UNIX 1)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM ONLY)
endmacro()

function(cpprest_find_boost)
  if(TARGET cpprestsdk_boost_internal)
    return()
  endif()

  if(IOS OR APPLE_TVOS)
    if(APPLE_TVOS AND EXISTS "${PROJECT_SOURCE_DIR}/../Build_tvOS/boost")
      set(BOOST_DIR "${PROJECT_SOURCE_DIR}/../Build_tvOS/boost")
    elseif(IOS AND EXISTS "${PROJECT_SOURCE_DIR}/../Build_iOS/boost")
      set(BOOST_DIR "${PROJECT_SOURCE_DIR}/../Build_iOS/boost")
    else()
      message(FATAL_ERROR "boost not found")
    endif()

    if (BOOST_DIR)
      project(ext_boost_thread)
      add_library(ext_boost_thread STATIC IMPORTED GLOBAL)
      set_target_properties(ext_boost_thread PROPERTIES
          IMPORTED_LOCATION "${BOOST_DIR}/lib/libboost_thread.a")

      project(ext_boost_chrono)
      add_library(ext_boost_chrono STATIC IMPORTED GLOBAL)
      set_target_properties(ext_boost_chrono PROPERTIES
          IMPORTED_LOCATION "${BOOST_DIR}/lib/libboost_chrono.a")
      
      set(Boost_LIBRARIES
        ext_boost_thread
        ext_boost_chrono
        CACHE INTERNAL "")
      set(Boost_INCLUDE_DIR "${BOOST_DIR}/include" CACHE INTERNAL "")
    else()
      set(IOS_SOURCE_DIR "${PROJECT_SOURCE_DIR}/../Build_iOS")
      set(Boost_LIBRARIES "${IOS_SOURCE_DIR}/boost.framework/boost" CACHE INTERNAL "")
      set(Boost_INCLUDE_DIR "${IOS_SOURCE_DIR}/boost.framework/Headers" CACHE INTERNAL "")
    endif()
  elseif(ANDROID)
    set(BOOST_DIR "${PROJECT_SOURCE_DIR}/../Build_android/Boost-for-Android/build/out/${ANDROID_ABI}")
    set(Boost_LIBRARIES "" CACHE INTERNAL "")
    set(Boost_INCLUDE_DIR "${BOOST_DIR}/include/boost-1_69" CACHE INTERNAL "")
  elseif(UNIX)
    set(Boost_USE_STATIC_LIBS ON)  # only find static libs
    find_package(Boost REQUIRED COMPONENTS system thread chrono)
  else()
    set(Boost_USE_STATIC_LIBS ON)  # only find static libs
    find_package(Boost REQUIRED COMPONENTS system date_time regex)
  endif()

  add_library(cpprestsdk_boost_internal INTERFACE)
  
  if(WIN32)
    # disable automatic linking
    target_compile_definitions(cpprestsdk_boost_internal INTERFACE BOOST_ALL_NO_LIB)
  endif()
  
  # FindBoost continually breaks imported targets whenever boost updates.
  if(1)
    target_include_directories(cpprestsdk_boost_internal INTERFACE "$<BUILD_INTERFACE:${Boost_INCLUDE_DIR}>")
    set(_prev)
    set(_libs)
    foreach(_lib ${Boost_LIBRARIES})
      if(_lib STREQUAL "optimized" OR _lib STREQUAL "debug")
      else()
        if(_prev STREQUAL "optimized")
          list(APPEND _libs "$<$<NOT:$<CONFIG:Debug>>:${_lib}>")
        elseif(_prev STREQUAL "debug")
          list(APPEND _libs "$<$<CONFIG:Debug>:${_lib}>")
        else()
          list(APPEND _libs "${_lib}")
        endif()
      endif()
      set(_prev "${_lib}")
    endforeach()
    #if (NOT IOS OR NOT EXISTS "${PROJECT_SOURCE_DIR}/../Build_iOS/boost")
      target_link_libraries(cpprestsdk_boost_internal INTERFACE "$<BUILD_INTERFACE:${_libs}>")
    #endif()
#[[
  else()
    if(ANDROID)
      target_link_libraries(cpprestsdk_boost_internal INTERFACE
        Boost::boost
        Boost::random
        Boost::system
        Boost::thread
        Boost::filesystem
        Boost::chrono
        Boost::atomic
      )
    elseif(UNIX)
      target_link_libraries(cpprestsdk_boost_internal INTERFACE
        Boost::boost
        Boost::random
        Boost::system
        Boost::thread
        Boost::filesystem
        Boost::chrono
        Boost::atomic
        Boost::date_time
        Boost::regex
      )
    else()
      target_link_libraries(cpprestsdk_boost_internal INTERFACE
        Boost::boost
        Boost::system
        Boost::date_time
        Boost::regex
      )
    endif()
]]
  endif()
endfunction()
