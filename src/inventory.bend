import Base

# Counts stay on the host as naturals. Every accepted edit transfers one
# item between a cell and its type's count; an occupied placement or an
# empty break changes neither. The receipt gates the actual world write.
type Transfer is Data:
  Transfer{solid: Bool, count: Nat, changed: Bool}

def transfer(put: Bool, solid: Bool, n: Nat) -> Transfer:
  match put solid:
    case False{} False{}:
      Transfer{False{}, n, False{}}
    case False{} True{}:
      Transfer{False{}, 1n+n, True{}}
    case True{} True{}:
      Transfer{True{}, n, False{}}
    case True{} False{}:
      match n:
        case 0n:
          Transfer{False{}, 0n, False{}}
        case 1n+p:
          Transfer{True{}, p, True{}}

def stock(m: Transfer) -> Nat:
  Transfer{solid, +n, changed} = m
  Bool.pick(Nat, solid, 1n+n, n)

def again(put: Bool, m: Transfer) -> Transfer:
  Transfer{solid, n, changed} = m
  transfer(put, solid, n)

def trace(actions: List<Bool>, m: Transfer) -> Transfer:
  match actions:
    case Nil{}:
      m
    case Con{put, rest}:
      trace(rest, again(put, m))

# The game creates eight slots; an edit preserves their number. An invalid
# slot is rejected, which also makes malformed selected types harmless.
def empty() -> List<&2, Nat>:
  [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n]

def count(xs: List<&2, Nat>, i: Nat) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{h, t}:
      match i:
        case 0n:
          h
        case 1n+p:
          count(t, p)

type Edit is Data:
  Edit{counts: List<&2, Nat>, changed: Bool}

def replace(t: List<&2, Nat>, m: Transfer) -> Edit:
  Transfer{solid, n, changed} = m
  Edit{Con{n, t}, changed}

def prepend(h: Nat, e: Edit) -> Edit:
  Edit{xs, changed} = e
  Edit{Con{h, xs}, changed}

def edit(xs: List<&2, Nat>, i: Nat, put: Bool, solid: Bool) -> Edit:
  match xs:
    case Nil{}:
      Edit{Nil{}, False{}}
    case Con{h, t}:
      match i:
        case 0n:
          replace(t, transfer(put, solid, h))
        case 1n+p:
          prepend(h, edit(t, p, put, solid))

def edited(e: Edit) -> List<&2, Nat>:
  Edit{xs, changed} = e
  xs
