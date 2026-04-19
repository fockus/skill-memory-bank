cmake_minimum_required(VERSION 3.20)
project(example_cpp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
add_executable(example_cpp main.cpp)

enable_testing()
