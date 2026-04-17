
# 🚀 Plymouth Custom Splash (Fedora)

Make your Linux boot screen truly yours.  
Replace the default Fedora splash with your own custom image — clean, minimal, and professional.

---

## ✨ Features

- 🎨 Custom boot logo (your PNG image)
- ⚙️ Fully automated setup via script
- 🌍 RU / EN interactive interface
- 🧠 Smart detection (GRUB, UEFI, packages)
- 🧩 Optional vendor logo removal (BGRT bypass)
- 🔄 Easy re-run to update your image

---

## 📦 Requirements

- Fedora Linux
- Root access (`sudo`)
- PNG image (recommended: 1920×1080, black background)

---

## ⚡ Quick Start

```bash
git clone https://github.com/yourusername/plymouth-custom-splash.git
cd plymouth-custom-splash
chmod +x plymouth-custom-setup.sh
sudo ./plymouth-custom-setup.sh
````

---

## 🖼️ Image Guidelines

For best results:

* Format: **PNG**
* Background: **black (#000000)**
* Resolution: **1920×1080**
* Layout: centered logo

Avoid:

* transparency (may show firmware background)
* small or thin text

---

## 🧠 How It Works

This tool configures **Plymouth**, the boot splash system in Linux.

Steps:

1. Creates a custom theme
2. Adds your image
3. Activates the theme
4. Rebuilds initramfs
5. Updates GRUB if needed

---

## 🧩 Optional: Remove Vendor Logo

Some systems show a firmware logo (ASUS, Lenovo, etc.) during boot.

The script can try to disable it using:

```
plymouth.use-simpledrm
```

⚠️ Note:

* Not guaranteed on all hardware
* Depends on BIOS/UEFI

---

## 🔧 Manual Commands

```bash
sudo plymouth-set-default-theme mytheme
sudo dracut -f
reboot
```

---

## 🐞 Troubleshooting

### Image not showing

```bash
sudo dracut -f
```

---

### script.so missing

```bash
sudo dnf install plymouth-plugin-script
```

---

### Vendor logo still visible

Edit GRUB:

```bash
sudo nano /etc/default/grub
```

Add:

```
plymouth.use-simpledrm
```

Then:

```bash
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo dracut -f
```

---

### Reboot blocked

```bash
systemctl reboot -i
```

---

## 📁 Project Structure

```
.
├── plymouth-custom-setup.sh
└── README.md
```

---

## 🛠️ Roadmap

* [ ] Animations (fade-in)
* [ ] Theme presets
* [ ] Multi-image support
* [ ] GUI version

---

## 🤝 Contributing

Pull requests are welcome.
Open an issue for ideas or bugs.

---

## ⚠️ Disclaimer

* Modifies boot configuration
* Tested on Fedora
* Use at your own risk

---

## 📜 License

MIT License

---

## ⭐ Support

If you like this project:

* Star the repo ⭐
* Share it
* Customize your system 🚀


