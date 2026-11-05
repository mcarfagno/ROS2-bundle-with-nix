cmake_minimum_required(VERSION 3.18)

# Orin (sm_87), keep in sync with cudaCapabilities in flake.nix, must be set before project()
set(CMAKE_CUDA_ARCHITECTURES 87)
set(CMAKE_CUDA_RUNTIME_LIBRARY Shared)

project(my_awesome_cuda LANGUAGES CXX CUDA)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(my_awesome_interfaces REQUIRED)
find_package(CUDAToolkit REQUIRED)

add_executable(cuda_talker src/cuda_talker.cpp src/vector_add.cu)
target_include_directories(cuda_talker PRIVATE include)
ament_target_dependencies(cuda_talker rclcpp my_awesome_interfaces)
target_link_libraries(cuda_talker CUDA::cudart)

install(TARGETS
  cuda_talker
  DESTINATION lib/${PROJECT_NAME})

install(DIRECTORY launch DESTINATION share/${PROJECT_NAME})

ament_package()
