import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { Ciswap } from "../target/types/ciswap"; // Tự động sinh ra từ IDL
import { assert } from "chai";

describe("ciswap", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace.ciswap as Program<Ciswap>;
  const signer = provider.wallet.publicKey;

  it("Calls hello_anchor instruction", async () => {
    // Derive PDA: [b"greeting", signer]
    const [helloPDA] = await anchor.web3.PublicKey.findProgramAddress(
      [Buffer.from("ciswap"), signer.toBuffer()],
      program.programId
    );

    const msg = "Xin chào từ Thầy!";

    // Call instruction
    const tx = await program.methods
      .helloAnchor(msg)
      .accounts({
        signer,
      })
      .rpc();

    console.log("✅ Gửi hello_anchor thành công:", tx);

    // Fetch lại account để đọc data (nếu struct có msg)
    const helloAccount = await program.account.helloAnchor.fetch(helloPDA);
    console.log("📦 Dữ liệu hello_anchor account:", helloAccount);

    // Nếu struct có field `msg`, test luôn:
    assert.equal(helloAccount.message, msg);
  });
});
