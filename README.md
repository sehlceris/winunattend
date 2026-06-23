# winunattend

Turn an **official Windows 10/11 ISO** into one that installs **without a
Microsoft account or an internet connection** — and without the Windows 11
TPM / Secure Boot / RAM / CPU checks. Runs entirely on **macOS** (Apple Silicon
or Intel). No Windows machine, no Rufus.

The output ISO:

- Boots on **bare-metal UEFI machines** and **Proxmox VMs** (BIOS + UEFI).
- Can be written to a USB stick with [WinDiskWriter](https://github.com/TechUnRestricted/WinDiskWriter).
- Can be attached as a CD in Proxmox / QEMU / UTM.

By default it lets you create your **own local account** interactively during
setup — no credentials are baked into the media.

```
winunattend ~/Downloads/Win11_25H2_English_x64.iso
# → ~/Downloads/Win11_25H2_English_x64-nomsa.iso
```

---

## Why

Recent Windows 11 builds (24H2 / 25H2) hide the "I don't have internet"
option and the old `OOBE\BYPASSNRO` / `no@thankyou.com` tricks are patched out.
The durable, Microsoft-supported path is an **`autounattend.xml`** answer file
placed at the root of the install media — Windows Setup reads it *before* OOBE,
so it survives the interactive-OOBE lockdowns. winunattend injects that file and
rebuilds a bootable ISO with `xorriso`.

## Install

```bash
git clone https://github.com/<you>/winunattend.git
cd winunattend
./winunattend --install-deps --help     # installs xorriso via Homebrew if missing
```

Requirements:

- macOS with [Homebrew](https://brew.sh)
- `xorriso` and `wimlib` (`brew install xorriso wimlib`, or pass `--install-deps`)
- `hdiutil`, `rsync`, `xmllint` (ship with macOS)
- Free disk space ≈ **2× the ISO size** (~18 GB for a typical Win11 ISO) for the
  temporary extracted tree plus the output.

Optionally symlink it onto your `PATH`:

```bash
ln -s "$PWD/winunattend" /usr/local/bin/winunattend
```

## Usage

```
winunattend [options] <source.iso>
```

| Option | Description |
| --- | --- |
| `-o, --output FILE` | Output ISO path. Default: `<source>-nomsa.iso` next to the source. |
| `--autounattend F` | Inject your own answer file instead of the built-in default. |
| `--arch ARCH` | `amd64` (default) or `arm64` — must match the Windows ISO. |
| `--lang LANG` | UI language / locale for the default answer file (default `en-US`). |
| `--keyboard ID` | Input locale id (default `0409:00000409`). |
| `--no-bypass-hw` | Do **not** bypass the Win11 TPM / Secure Boot / RAM / CPU checks. |
| `--noprompt` | Boot without the "Press any key to boot from CD" prompt (hands-off VMs). |
| `--no-split` | Do **not** split a >4 GB `install.wim` (advanced; may break the ISO). |
| `--volid LABEL` | Override the output volume label (default: copied from source). |
| `--install-deps` | Install missing dependencies (xorriso) via Homebrew. |
| `--keep-work` | Keep the temporary working directory. |
| `-y, --yes` | Assume "yes" to prompts (non-interactive). |
| `-h, --help` / `-V, --version` | Help / version. |

### What the default answer file does

- Re-enables the offline ("limited setup") OOBE path so you can create a
  **local account** without a Microsoft account or network.
- Bypasses the Windows 11 **TPM 2.0 / Secure Boot / RAM / CPU / storage**
  requirement checks (great for Proxmox and older laptops).
- Accepts the EULA and hides the product-key prompt.

It does **not** create an account, set a password, pick an edition, partition
the disk, or remove any apps — you stay in control during setup.

### Bring your own answer file (more customization)

For debloat, an auto-created local account, VirtIO drivers, edition selection,
etc., generate an answer file with the excellent
[schneegans.de unattend generator](https://schneegans.de/windows/unattend-generator/)
and pass it directly:

```bash
winunattend --autounattend ./autounattend.xml -o ~/Win11_custom.iso Win11.iso
```

winunattend strips a UTF-8 BOM if present and validates the XML before
injecting it. (Tip: in the generator pick **"Let Windows Setup create a local
account"** for a fully hands-off install.)

## How it works

Microsoft's Windows ISOs keep **all** their content in a **UDF** filesystem; the
ISO 9660 side is just a stub `README.TXT`. `xorriso` can't read or write UDF, so
editing the ISO "in place" would silently drop the entire OS. winunattend
therefore extracts and rebuilds:

1. Reads the source's volume label and El Torito boot record with `xorriso`.
2. **Mounts** the source with `hdiutil` (macOS reads UDF natively) and copies the
   full tree into a temporary staging dir.
3. If `sources/install.wim` is larger than 4 GiB, **splits** it into
   `install.swm` / `install2.swm` / … parts with `wimlib` (Windows Setup reads
   these natively). This keeps every file under the ISO 9660 / FAT32 4 GiB limit.
4. Adds the answer file at `/autounattend.xml`.
5. **Authors a fresh bootable ISO** with `xorriso -as mkisofs` — ISO 9660 +
   Joliet, reusing the source's original El Torito boot images for both BIOS
   (`boot/etfsboot.com`) and UEFI (`efi/microsoft/boot/efisys.bin`).
6. Verifies the answer file and `sources/boot.wim` are present and the boot
   record survived.

> **Why split the WIM?** ISO 9660 (and FAT32) cap a single file at 4 GiB. A
> modern `install.wim` is often 5–8 GB. Splitting into `.swm` parts is the
> portable fix that works everywhere — booting a CD in Proxmox, and writing to a
> FAT32 USB with WinDiskWriter (which then needs no further splitting).

## Proxmox VM notes

The default ISO bypasses the hardware checks, but for a clean install use:

- **Machine** `q35`, **BIOS** `OVMF (UEFI)` + an EFI disk.
- A **vTPM 2.0** (cleaner than relying on the bypass long-term).
- Disk on **VirtIO SCSI** or VirtIO Block.

Windows Setup has **no VirtIO storage drivers**, so a VirtIO disk shows up as
"no drives found". Either:

- Attach the [virtio-win ISO](https://github.com/virtio-win/virtio-win-pkg-scripts)
  as a second CD and click **Load driver → `vioscsi\w11\amd64`** during setup, or
- Generate your answer file at schneegans.de with the **VirtIO drivers** option
  enabled and pass it via `--autounattend` (then attach virtio-win as a 2nd CD).

Example:

```bash
qm create 200 --name win11 --memory 8192 --cores 4 --cpu host \
  --bios ovmf --machine q35 \
  --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=1 \
  --tpmstate0 local-lvm:1,version=v2.0 \
  --scsihw virtio-scsi-single --scsi0 local-lvm:64,iothread=1 \
  --net0 virtio,bridge=vmbr0 \
  --cdrom local:iso/Win11_custom.iso \
  --ide0 local:iso/virtio-win.iso,media=cdrom \
  --ostype win11 --boot order=scsi0
```

## Writing to USB (bare metal)

Use [WinDiskWriter](https://github.com/TechUnRestricted/WinDiskWriter) on macOS
— it handles the FAT32/`install.wim` split automatically. Boot the target
machine from the USB in UEFI mode.

## Security notes

- The default answer file contains **no credentials** — you create your account
  during setup.
- If you supply an answer file that *creates* a local account, the password is
  stored in **plaintext** inside `autounattend.xml` and is copied to
  `C:\Windows\Panther\` after install. Use a throwaway password and change it
  (or delete the Panther copies) after first login. Treat such an ISO as
  sensitive.
- Bypassing TPM / Secure Boot is fine for labs and VMs. For a daily-driver
  bare-metal machine, prefer giving it a real TPM.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| MS-account prompt still appears | Make sure the answer file is at the ISO root and named exactly `autounattend.xml` (the tool does this). On a brand-new build, regenerate from schneegans.de — it tracks Microsoft's changes. |
| "No drives found" on Proxmox | VirtIO storage driver not loaded — attach `virtio-win.iso` as a 2nd CD (see above) or use a SATA disk. |
| "Windows could not apply the unattend answer file" | A custom answer file's `<DiskConfiguration>` is too specific — regenerate with the vanilla whole-disk option. |
| Stuck at "Press any key to boot from CD" | Expected on first CD boot; press a key. For hands-off VMs, generate media using the `efisys_noprompt.bin` boot variant. |

## Disclaimer

For your own machines and lab VMs. You must own a valid Windows license. This
tool does not bypass activation or licensing — only the setup-time account/
hardware gates, which Windows fully supports via answer files.

## License

[MIT](LICENSE).
