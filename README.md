# Inception of Things

## Pre-requisites

Depend on the subject, we need to setup everything in the VM which need to be the latest stable version OS and currectly is Debain12.

```sh
# For AMD64 architecture (For campus computer)
wget https://cdimage.debian.org/cdimage/archive/12.9.0/amd64/iso-cd/debian-12.9.0-amd64-netinst.iso

# For ARM64 architecture (For my macos)
wget https://cdimage.debian.org/cdimage/archive/12.9.0/arm64/iso-cd/debian-12.9.0-arm64-netinst.iso
```

To enable nested virtualization in VirtualBox, allowing a guest VM to run its own VMs,

1. Using the VirtualBox GUI:
    - Select the guest VM in the VirtualBox Manager.
    - Click "Settings" to open the VM's settings window.
    - Navigate to "System" > "Processor".
    - Check the box labeled "Enable Nested VT-x/AMD-V".
    - Click "OK" to save the changes. 

2. Using the VBoxManage command-line tool: 

```sh
VBoxManage modifyvm "<YourVirtualMachineName>" --nested-hw-virt on
```


## Setup Host VM

Add current user to `sudo` group

```sh
su -
sudo usermod -aG sudo <USER>
```

Install the required packages and tools

```sh
./scripts/setup_host.sh
```

