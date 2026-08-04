# AES S-Box Implementation (kecc_aes_k_xif)

This document describes the AES S-Box circuit used by the `kecc_aes_k_xif`
coprocessor in this tree, and how it compares to the alternative S-box
backends available in the sibling `kecc-aes-k` project.

## Source

- File: [kecc_aes_k_xif/hw/kecc_aes_k_xif_aes_sboxes.sv](kecc_aes_k_xif/hw/kecc_aes_k_xif_aes_sboxes.sv)
- Ported from `aes-ext/cva6/core/crypto/crypto_sboxes.sv` (only the AES-relevant
  modules were kept; the SM4-only sbox modules from the original file were
  dropped).
- That file is itself a converted/simplified version of `riscv_crypto_fu_sboxes.v`
  from the [riscv-crypto](https://github.com/riscv/riscv-crypto) repository,
  originally authored by Markku-Juhani O. Saarinen (PQShield Ltd.).

## Circuit design

The implementation is a **purely combinational**, ROM-free circuit built from
the tower-field (GF(256) → GF(2⁴)²) decomposition of the AES S-box, using
Nyberg's affine isomorphism to reduce the S-box to a shared multiplicative
inverse plus direction-specific linear layers. Concretely, each direction
(`riscv_crypto_aes_fwd_sbox` / `riscv_crypto_aes_inv_sbox`) is built from
three chained sub-circuits:

1. **`top`** — linear layer, direction-specific
   (`riscv_crypto_sbox_aes_top` for forward, `riscv_crypto_sbox_aesi_top`
   for inverse), maps the input byte into the GF(2⁴)² domain.
2. **`mid`** — `riscv_crypto_sbox_inv_mid`, the nonlinear GF(256)
   multiplicative-inverse network, **shared** between the forward and
   inverse S-box.
3. **`out`** — linear layer, direction-specific
   (`riscv_crypto_sbox_aes_out` / `riscv_crypto_sbox_aesi_out`), maps back
   to the AES byte domain.

There is no clock, reset, or request/response handshake anywhere in this
file — it is a single-cycle (0-latency) combinational function, `fx = f(in)`.

## Citation

- **[BoPe12]** Boyar J., Peralta R., *"A Small Depth-16 Circuit for the AES
  S-Box."* Proc. SEC 2012, IFIP AICT 376, Springer, pp. 287–298 (2012).
  DOI: [10.1007/978-3-642-30436-1_24](https://doi.org/10.1007/978-3-642-30436-1_24).
  Preprint: <https://eprint.iacr.org/2011/332.pdf>
- **[Ny93]** Nyberg K., *"Differentially Uniform Mappings for Cryptography"*,
  Proc. EUROCRYPT '93, LNCS 765, Springer, pp. 55–64 (1993).
  DOI: [10.1007/3-540-48285-7_6](https://doi.org/10.1007/3-540-48285-7_6)

## Comparison with `kecc-aes-k`'s v4 configurable `aes_sbox`

The sibling `kecc-aes-k` project (`../../kecc-aes-k`) exposes an
elaboration-time-selectable `aes_sbox` (v4) with three interchangeable
backends (`rtl/aes_sbox.sv`, `rtl/aes_sbox_pkg.sv`). None of the three is the
same circuit as the one described above, though `AES_SBOX_IMPL_BP` shares
its academic lineage (Boyar/Peralta, no ROM):

| | ROM (`_serial_rom` / `_dp_rom`) | `aes_sbox_bp` / `aes_sbox_bp_byte` (v4's `BP`) | This tree's `kecc_aes_k_xif_aes_sboxes.sv` |
|---|---|---|---|
| Circuit source | 512×8 lookup table | Circuit Minimization Work project's flat straight-line program (`SLP_AES_113.txt`, 113 gates; `Sinv.txt`, 121 gates — Boyar/Peralta/Calik) | riscv-crypto's `top`/`mid`/`out` decomposition ([BoPe12] + Nyberg [Ny93]) |
| Structure | Memory | Flat gate list, forward and inverse fully separate, no sharing | Layered: nonlinear middle stage **shared** between forward/inverse, direction-specific linear top/out |
| Interface | Registered, `req_valid`/`req_ready`/`rsp_valid`/`rsp_ready` handshake, 1–4 cycle latency | Registered, same handshake, 1-cycle latency | Purely combinational, no clock/reset/handshake |

**Note:** because of the interface difference, this circuit cannot be
dropped into `kecc-aes-k`'s `SBOX_IMPL` selector as-is — it would need a
new `AES_SBOX_IMPL_*` arm plus a synchronous wrapper to match the shared
`req`/`rsp` handshake contract every existing v4 backend implements.
