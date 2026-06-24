{
  services.udev.extraRules = ''
    # Deauthorize the Logitech C270 webcam's audio interface so snd-usb-audio never binds and no ALSA capture device is created.
    # The camera (uvcvideo) is unaffected — only USB interface class 01 (Audio) is matched.
    # This ONE LINE drops Voxize startup time by 20× ...and who uses their webcam's microphone anyway?
    SUBSYSTEM=="usb", DRIVER=="snd-usb-audio", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="0825", ATTR{authorized}="0"
  '';
}
