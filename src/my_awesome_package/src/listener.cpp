#include <memory>

#include "rclcpp/rclcpp.hpp"
#include "my_awesome_interfaces/msg/greeting.hpp"

class Listener : public rclcpp::Node
{
public:
  Listener()
  : Node("listener")
  {
    subscription_ = this->create_subscription<my_awesome_interfaces::msg::Greeting>(
      "greeting", 10, std::bind(&Listener::topic_callback, this, std::placeholders::_1));
  }

private:
  void topic_callback(const my_awesome_interfaces::msg::Greeting::SharedPtr msg)
  {
    RCLCPP_INFO(this->get_logger(), "I heard: '%s'", msg->message.c_str());
  }

  rclcpp::Subscription<my_awesome_interfaces::msg::Greeting>::SharedPtr subscription_;
};

int main(int argc, char * argv[])
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<Listener>());
  rclcpp::shutdown();
  return 0;
}
