// sys_log.h - shim for the test build: the one logging call cpu_i8080.cpp makes
// (LOG_INFO, on an unrecognized opcode or an unhandled access) goes to stderr.
// AAE's own sys_log.h is not used here.
#ifndef SYS_LOG_SHIM_H
#define SYS_LOG_SHIM_H

#include <cstdio>
#include <cstdlib>

#define LOG_INFO(...)  (std::fprintf(stderr, "[cpu_i8080] " __VA_ARGS__), std::fprintf(stderr, "\n"))
#define LOG_DEBUG(...) LOG_INFO(__VA_ARGS__)
#define LOG_ERROR(...) LOG_INFO(__VA_ARGS__)

#endif
