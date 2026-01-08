Background and Previous Work

The way things are set up now, the Basys3 FPGA can already make a working VGA output. VGA timing, syncing, and basic color output have been tested, including test patterns like color bars that are made directly in hardware. This proves that the hardware VGA pipeline, clocking, and output limitations are right.

But the way to get VGA output right now is controlled by hardware, and it doesn't allow pixel data from the NEORV32 processor that is controlled by software. Right now, there is no framebuffer or memory-backed way to dynamically update displayed information that can be accessed by the CPU.

This recovery effort makes it clear that it does not try to reimplement or replace VGA timing or signal-generation code that is already in place.

The Range of This Recovery Job

The goal of this project is to make a software-visible framebuffer interface that lets the NEORV32 processor put pixel data into memory so that the VGA pipeline can read it.

This includes
Establishing a VRAM/framebuffer model that works for VGA scanout.
Setting up a clean edge of the link between
CPU write-side access, which can be done through memory-mapped registers or external bus methods.
VGA hardware for read-side scanout

Giving RTL modules that can be built up step by step and Ada driver stubs that show
The memory structure that is meant to be used.
Expectations for control at the register
How it works with current VGA gear.

At this point, the work is only scaffolding. Intent is compiled and documented by modules, but they aren't fully connected to the top-level design yet.

Clear Non-Goals

To avoid overlap or regression, the following things won't be included in this healing window:
Changing or changing timing generators for VGA.
Changing how VGA encodes color has already been shown to work.
Putting in camera capture, image analysis, or DMA logic.
Claiming that the framebuffer works from start to finish in this step.

These limitations make sure that the work is done in steps, can be checked, and doesn't get in the way of progress on the same task by other teams working in parallel.

Purpose of the Software Interface

The goal of the software interface is to make framebuffer memory available to Ada apps that run on NEORV32. To software, the framebuffer looks like a part of memory that can be written to, or a small, register-controlled view of VRAM.

Initial verification will rely on software to create simple patterns (like solid fills, gradients, and checkerboards) to make sure that the addressing, byte enables, and scanout behavior are right.

Ada-side drivers are set up to work with this interface and will be expanded a little at a time after RTL integration is accepted.

The ability to be integrated with future cameras

This framebuffer work is an important step in the architecture process that needs to be done before a camera can be used.

It is believed that the long-term data will:

Camera Sensor → Logic for Taking Pictures → Framebuffer / VRAM → VGA Scanout

By setting up a CPU-visible framebuffer now, future camera work can focus on a memory layout and software promise that are known, so there is no need to change how the display path works. This lowers the risk of integration and helps with staged testing.

Things That Must Be Done During This Recovery Phase

During the recovery time, this work will give us:

A defined framebuffer design and interface.
RTL stubs and integration placeholders showing how the wiring should be done.
Ada driver stubs that show the software API that is planned.
Traceability notes that connect framebuffer work to the needs of the overall system.

At this stage, these products put clarity, reviewability, and alignment with the original project goals ahead of feature completeness.
