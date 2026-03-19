---
weight: 1
title: "FPGAs : Working with DPU Part 2"
date: 2026-03-19T09:00:00+00:00
lastmod: 2026-03-19T09:00:00+00:00
draft: false
author: "Jack Bonnell"
authorLink: "https://jackbonnell.dev"
description: "Working with DPU on FPGAs - Part 2"
images: []

tags: ["fpga", "blog"]
categories: ["general"]

lightgallery: true

toc:
  enable: false
  auto: false

share:
  enable: false
---
<div class="about-card">
This week... probably more like 2/3 weeks. I have been trying to get the DPU running on PetaLinux. This took a reasonable amount of work configuring the PetaLinux project to actually get it working. Currently the DPU is not supported on PetaLinux 2025.2 as far as I could see, so it took a bit of work to get it running.

# Overview

This project is for the Xilinx 2025.2 toolchain. In this post I'll describe how I created a PetaLinux project to run the DPUCZDX8G using the Vivado flow.

# Step 1: Creating the PetaLinux project

First, source the PetaLinux settings script for the 2025.2 toolchain (`<petalinux_folder>/settings.sh`), then create the base project for the Ultra96-V2 DPU design:

```bash
petalinux-create --type project --template zynqMP --name ultra96v2_dpu
```

# Step 2: Configure the project

Before configuring the PetaLinux project, make sure to copy your exported XSA file (named `ultra96v2_dpu.xsa`) into a convenient location.

Now change into your new project directory:

```
cd ultra96v2_dpu
```

To configure the hardware, pass your XSA file to the project:

```
petalinux-config --get-hw-description ../ultra96v2_dpu.xsa
```

## Setting Serial and Filesystem

Next, configure the serial port settings to use UART1 and ensure that all relevant serial console options are set correctly for the Ultra96V2.

<div class="config-img">
  {{< image src="/fpga-dpu-part-2/serial_setting.png" alt="PetaLinux UART1 Serial Config" title="Set All UART1 Serial Console Options in PetaLinux" >}}
</div>

- **Subsystem AUTO Hardware Settings → Serial Settings**
  - `Primary stdin` : `psu_uart_1`
  - `Primary stdout` : `psu_uart_1`
  - `Primary stderr` : `psu_uart_1`
  - `Serial port` : `psu_uart_1`

For filesystem configuration, select `ext4` as the root filesystem type:

<div class="config-img">
  {{< image src="/fpga-dpu-part-2/Root_file_type.png" alt="PetaLinux ext4 Filesystem Config" title="Set ext4 Root Filesystem in PetaLinux" >}}
</div>

- **Image Packaging Configuration → Root filesystem type**
  - Select: `ext4`

## Device-tree: Set Machine Name

You will also want to set the machine name in the device tree settings to ensure compatibility with the Ultra96-V2 board.

<div class="config-img">
  {{< image src="/fpga-dpu-part-2/DT_settings.png" alt="PetaLinux Machine Name Config" title="Set Machine Name to avnet-ultra96-rev1 in PetaLinux DTG" >}}
</div>

- **DTG Settings → Machine Name**
  - Change this value to: `avnet-ultra96-rev1`

## Add `meta-vitis` Yocto layer

You can get this from AMD’s public GitHub repository: [Xilinx/meta-vitis (rel-v2024.2)](https://github.com/Xilinx/meta-vitis/tree/rel-v2024.2).

Then, in `petalinux-config`, add `meta-vitis` as a user layer:

- **Yocto Settings → User Layers**

<div class="config-img">
  {{< image src="/fpga-dpu-part-2/user_layers_meta_vitis.png" alt="PetaLinux User Layers meta-vitis" title="Add meta-vitis as a PetaLinux user layer" >}}
</div>

After adding the layer, open `project-spec/meta-user/meta-vitis/recipes-vai/vart/vart_3.5.bb` and ensure the following line is commented out:

```text
# PACKAGECONFIG:append = " vitis"
```

# Step 3: Add replacement `recipes-vai` 

As a final preparation step before building, add the replacement [recipes-vai](https://adaptivesupport.amd.com/sfc/servlet.shepherd/document/download/069KZ000000SFPsYAO?operationContext=S1) folder provided by AMD into `project-spec/meta-user/` as well. ([This part was referenced from LogicTronix's hackster.io Project](https://www.hackster.io/LogicTronix/vitis-ai-3-5-with-petalinux-2024-2-36c9f7))


# Step 4: Update Kernel BSP

In your BSP layer under `recipes-kernel/linux/linux-xlnx`, make sure the kernel configuration enables enough CMA memory and the DPU driver:

```text
CONFIG_CMA_SIZE_MBYTES=1024
CONFIG_XILINX_DPU=y
```

# Step 5: Enable rootfs packages for Vitis AI and tooling

First, make sure the key packages are listed in `project-spec/meta-user/conf/user-rootfsconfig` so they are always selected when you run the rootfs config:

```text
CONFIG_gpio-demo
CONFIG_peekpoke
CONFIG_packagegroup-vitisai
CONFIG_vart
CONFIG_xir
CONFIG_unilog
CONFIG_dnf
CONFIG_nfs-utils
CONFIG_resize-part
CONFIG_vitis-ai-library-dev
CONFIG_vitis-ai-library-dbg
```

Then, in the root filesystem configuration (`petalinux-config -c rootfs`), enable the following options to pull in the required system, Vitis AI, debugging and convenience packages:

```text
CONFIG_system-zynqmp=y
CONFIG_dnf=y
CONFIG_e2fsprogs-mke2fs=y
CONFIG_fpga-manager-script=y
CONFIG_mtd-utils=y
CONFIG_can-utils=y
CONFIG_nfs-utils=y
CONFIG_pciutils=y
CONFIG_run-postinsts=y
CONFIG_libdfx=y
CONFIG_xrt=y
CONFIG_xrt-dev=y
CONFIG_xrt-dbg=y
CONFIG_zocl=y
CONFIG_zocl-dev=y
CONFIG_zocl-dbg=y
CONFIG_udev-extraconf=y
CONFIG_linux-xlnx-udev-rules=y
CONFIG_packagegroup-core-boot=y
CONFIG_tcf-agent=y
CONFIG_bridge-utils=y
CONFIG_dosfstools=y
CONFIG_resize-part=y
CONFIG_u-boot-tools=y
CONFIG_imagefeature-ssh-server-openssh=y
CONFIG_imagefeature-hwcodecs=y
CONFIG_imagefeature-package-management=y
CONFIG_imagefeature-empty-root-password=y
CONFIG_imagefeature-serial-autologin-root=y
CONFIG_Init-manager-systemd=y
CONFIG_packagegroup-vitisai=y
CONFIG_unilog=yk
CONFIG_vart=y
CONFIG_vitis-ai-library-dbg=y
CONFIG_vitis-ai-library-dev=y
CONFIG_xir=y
```

# Step 6: Add DPU drivers

Clone the DPU driver repository directly into `project-spec/meta-user/recipes-kernel/` so the recipes are picked up by the build.
Use: [JackBonnellDevelopment/Xilinx_DPU_Driver](https://github.com/JackBonnellDevelopment/Xilinx_DPU_Driver).

# Step 7: Update the device tree for DPU

Before building, update the `system-user.dtsi` so that the DPU node in `pl.dtsi` is extended with the correct compatible string and properties. Replace the contents of `project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi` with:

```dts
/include/ "system-conf.dtsi"

/* Extend the auto-generated DPU node from pl.dtsi */
&dpuczdx8g_0 {
	compatible = "xlnx,dpuczdx8g-4.1", "xilinx,dpu";
	core-num = <1>;
};
```

This ensures the DPU kernel module can correctly bind to the DPU instance in your design.

# Step 8: Build and package images

With the configuration and device tree updates complete, build the PetaLinux project and generate the boot files and WIC image (following the same flow described in the test-pattern-generator pipeline post):

```bash
petalinux-build
petalinux-package --boot --format BIN \
  --fsbl ./images/linux/zynqmp_fsbl.elf \
  --u-boot \
  --pmufw ./images/linux/pmufw.elf \
  --fpga \
  --dtb ./images/linux/system.dtb \
  --force
petalinux-package --wic --force
```
This will generate the full `.wic` image file, typically in `images/linux/`, suitable for direct writing to your SD card.

### Step 9. Write the WIC Image to SD Card

Now that you have the `.wic` image, you can write it to your SD card using [balenaEtcher](https://www.balena.io/etcher/) or a similar tool:

<div class="sd-flash-img">
  {{< image src="/fpga-test-pattern-generator-pipeline/flash_sd_card.png" alt="Flashing SD Card with Etcher" title="Using balenaEtcher to flash the .wic image to an SD card" >}}
</div>

1. **Insert** the SD card into your PC.
2. **Open** balenaEtcher.
3. **Select** the generated `.wic` image file (e.g., `images/linux/plnx-aarch64.wic`).
4. **Choose** your SD card as the target.
5. **Click "Flash"** to program the SD card.

After Etcher completes, safely eject the SD card and insert it into your Ultra96-V2 board to boot your new 
image.

## Step 10: Verify the DPU is running

Once the board has booted, you can connect to the Linux console over serial (for example, using [PuTTY](https://www.putty.org/) on Windows):

1. **Open PuTTY** and select the *Serial* connection type.  
2. Set the *Serial line* to the COM port used by your Ultra96-V2 (for example, `COM6`).  
   - **Baud rate:** `115200`  
   - **Data bits:** `8`  
   - **Stop bits:** `1`  
   - **Parity:** `None`  
   - **Flow control:** `None`  
3. Click **Open**, log in to the board, and run:

```bash
xdputil query
```

This should print out information about the DPU core, confirming that the accelerator is visible and configured correctly.

<div class="config-img">
  {{< image src="/fpga-dpu-part-2/xdputil_query.png" alt="xdputil query DPU status" title="Checking DPU status with xdputil query" >}}
</div>

</div>

