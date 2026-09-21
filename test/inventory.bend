import Base
import ../src/inventory.bend as Inventory

def expect(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("ok " ++ name)
    case False{}:
      IO.die(Unit, 1, "failed " ++ name)

def counts(e: Inventory.Edit, +i: Nat, n: Nat, changed: Bool) -> Bool:
  Inventory.Edit{xs, did} = e
  Nat.is_eq(Inventory.count(xs, i), n) && Bool.not(Bool.xor(did, changed))

def main() -> IO(Unit):
  do IO<Unit>:
    expect(counts(Inventory.edit(Inventory.empty(), 7n, False{}, True{}), 7n, 1n, True{}), "collect into last slot")
    expect(counts(Inventory.edit(Inventory.empty(), 0n, True{}, False{}), 0n, 0n, False{}), "empty slot rejects placement")
    expect(counts(Inventory.edit([1n, 2n, 3n], 1n, True{}, False{}), 1n, 1n, True{}), "placement spends one")
    expect(counts(Inventory.edit([1n, 2n, 3n], 1n, False{}, True{}), 0n, 1n, True{}), "earlier slot is untouched")
    expect(counts(Inventory.edit([1n, 2n, 3n], 1n, False{}, True{}), 2n, 3n, True{}), "later slot is untouched")
    expect(counts(Inventory.edit([1n, 2n, 3n], 8n, False{}, True{}), 1n, 2n, False{}), "invalid slot rejects edit")
    expect(counts(Inventory.edit([1000n], 0n, False{}, True{}), 0n, 1001n, True{}), "counts exceed HUD range")
