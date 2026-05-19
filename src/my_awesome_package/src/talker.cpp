#include <chrono>
#include <memory>

#include "my_awesome_interfaces/msg/greeting.hpp"
#include "rclcpp/rclcpp.hpp"

using namespace std::chrono_literals;

class Talker : public rclcpp::Node {
public:
  Talker() : Node("talker"), count_(0) {
    publisher_ = this->create_publisher<my_awesome_interfaces::msg::Greeting>(
        "greeting", 10);
    timer_ =
        this->create_wall_timer(1s, std::bind(&Talker::timer_callback, this));
  }

private:
  void timer_callback() {
    auto msg = my_awesome_interfaces::msg::Greeting();
    msg.message = "Nix is awesome " + std::to_string(count_++);
    RCLCPP_INFO(this->get_logger(), "Publishing: '%s'", msg.message.c_str());
    publisher_->publish(msg);
  }

  rclcpp::Publisher<my_awesome_interfaces::msg::Greeting>::SharedPtr publisher_;
  rclcpp::TimerBase::SharedPtr timer_;
  size_t count_;
};

int main(int argc, char *argv[]) {
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<Talker>());
  rclcpp::shutdown();
  return 0;
}
