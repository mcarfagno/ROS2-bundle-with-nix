cmake_minimum_required(VERSION 3.8)
project(my_awesome_package)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(my_awesome_interfaces REQUIRED)

add_executable(talker src/talker.cpp)
ament_target_dependencies(talker rclcpp my_awesome_interfaces)

add_executable(listener src/listener.cpp)
ament_target_dependencies(listener rclcpp my_awesome_interfaces)

install(TARGETS
  talker
  listener
  DESTINATION lib/${PROJECT_NAME})

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
