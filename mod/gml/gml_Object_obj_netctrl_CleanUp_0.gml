if (global.coop.socket >= 0)
{
    network_destroy(global.coop.socket);
    global.coop.socket = -1;
}
if (buffer_exists(global.coop.rx_buf))
{
    buffer_delete(global.coop.rx_buf);
}
global.coop.state = "idle";
show_debug_message("[coop] netctrl destroyed");
