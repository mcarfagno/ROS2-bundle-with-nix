#include <chrono>
#include <memory>

#include "my_awesome_cuda/vector_add.hpp"
#include "my_awesome_interfaces/msg/greeting.hpp"
#include "rclcpp/rclcpp.hpp"

using namespace std::chrono_literals;

class CudaTalker : public rclcpp::Node {
public:
  CudaTalker() : Node("cuda_talker"), device_(device_name()) {
    publisher_ = this->create_publisher<my_awesome_interfaces::msg::Greeting>(
        "greeting", 10);
    timer_ = this->create_wall_timer(
        1s, std::bind(&CudaTalker::timer_callback, this));
  }

private:
  void timer_callback() {
    auto msg = my_awesome_interfaces::msg::Greeting();
    msg.message = "Nix is awesome on " + device_ + ", GPU sum " +
                  std::to_string(vector_add(1000));
    RCLCPP_INFO(this->get_logger(), "Publishing: '%s'", msg.message.c_str());
    publisher_->publish(msg);
  }

  rclcpp::Publisher<my_awesome_interfaces::msg::Greeting>::SharedPtr publisher_;
  rclcpp::TimerBase::SharedPtr timer_;
  std::string device_;
};

int main(int argc, char *argv[]) {
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<CudaTalker>());
  rclcpp::shutdown();
  return 0;
}
