# Bazzite-Deepin-OGC

This project automates the creation of a customized, Atomic Fedora-based gaming operating system. It merges the stellar foundation of **Bazzite** (from Universal Blue) with the **OGC Kernel** (optimized for enhanced gaming and desktop responsiveness) and the **Deepin Desktop Environment** (DDE).

## 🚀 Goal of the Project

The core objective is to deliver a cutting-edge Linux gaming experience featuring a gorgeous, lightweight desktop GUI right out of the box, without sacrificing the stability of an immutable OS. 

Because managing complex filesystem layers and replacing the default desktop environments (KDE/GNOME) on read-only Atomic systems is traditionally difficult, **this project fully automates the entire process in the cloud**.

## 🛠 How It Works

Instead of users running destructive scripts or complicated command-line setups on their local machines, this repository acts as a blueprint. Using **BlueBuild** and **GitHub Actions**, the OS is re-assembled natively whenever changes are pushed:

1. **Base Layer:** It pulls the latest `ublue-os/bazzite` unstable container image.
2. **Package Modification:** It seamlessly strips out unneeded packages while injecting the complete **Deepin Desktop Environment** (DDE) directly into the filesystem image via DNF5, ensuring compatibility.
3. **Optimizations:** It detects and enables Deepin-specific systemd daemon services dynamically.
4. **Game Mode Integrations:** It automatically seeds Game Mode returning shortcut layers into the user skeleton (`/etc/skel`), guaranteeing gamers always have a quick way to switch back to Gamescope.
5. **ISO Generation:** The output container is packaged back into a bootable offline USB Installer (`.iso`) through the `build-container-installer` pipeline.

Everything is completely hands-off. The final result is pushed directly to the GitHub Container Registry as an OCI Container and exposed as a downloadable ISO Artifact.

## 💾 Installation

### Option 1: Clean Install via USB (Recommended)
You can directly download the compiled ISO and flash it.
1. Navigate to the **Actions** tab in this repository.
2. Click on the most recent successful run of `Build Bazzite-Deepin-OGC`.
3. Scroll down to the **Artifacts** section and download the `bazzite-deepin-ogc-installer.iso`.
4. Flash the ISO to a USB drive using Rufus or BalenaEtcher and boot your machine.

### Option 2: Rebase from an Existing Bazzite Build
If you are already running Bazzite on your machine, you can magically convert your operating system over to this customized build without losing your personal data.
Simply run the following command in your terminal:

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/muxd22-alt/bazzite-deepin-ogc:latest
```

Reboot, and you will enter the Deepin Desktop Environment!

## Development & Maintenance

This workflow utilizes the `recipe.yml` structure. To add packages, remove dependencies, or inject system configurations:
- Modify `recipes/recipe.yml`.
- Any custom files/executables dropped into `files/` will automatically be seeded into the root filesystem `/`.
- GitHub Actions automatically handles the container compilation and ISO validation.

## 🙏 Special Thanks & Credits

This project stands on the shoulders of giants. A massive thank you to the incredible open-source communities that made this possible:

*   **[Bazzite](https://bazzite.gg/) & Universal Blue:** For providing an incredibly robust, gaming-optimized, immutable Fedora atomic base image. You revolutionized Linux gaming reliability.
*   **[Open Gaming Collective (OGC)](https://opengamingcollective.org/):** For their relentless optimizations and custom patches that squeeze every ounce of performance and responsiveness out of the hardware.
*   **[Deepin Desktop Environment (DDE)](https://www.deepin.org/):** For crafting one of the most stunningly beautiful, elegant, and modern desktop experiences available on Linux today.