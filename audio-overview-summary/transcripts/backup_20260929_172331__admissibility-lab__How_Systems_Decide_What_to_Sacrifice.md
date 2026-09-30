# backup_20260929_172331/admissibility-lab/How_Systems_Decide_What_to_Sacrifice

The framework described here—referred to as the four‑factor characterization for accountable recoverable degradation, or ARDO—is designed to ensure that systems can degrade gracefully and reliably under conditions of overload. The four interlocking factors are:

1. **DO (Degradation Operator Works)**: This factor ensures that there is a functional mechanism in place—such as an Apollo uniform restart or a safe pruning algorithm—that allows the system to transition mathematically into an obligation‑preserving state without failure.

2. **FO (Fixed Obligation Model)**: The core invariant must be declared and fixed before any operation begins, independent of the outcome. This means that priorities cannot be redefined after the fact; they must be set beforehand based on what is truly essential for the system’s purpose.

3. **HO (Historical Sufficiency)**: Every task intended to resume later must retain a representation that guarantees its future continuation—known as decontinuation tokens—not just raw data dumps. This ensures that critical information needed for recovery is preserved and can be accessed when necessary.

4. **WO (Witness Object)**: Each excluded, suspended, or aborted task must receive an externally visible disposition witness. This prevents silent forgetting by ensuring accountability and traceability of every state change within the system.

The interlocking nature of these factors means that all four must be present simultaneously for a degradation process to succeed gracefully; lacking any one leads to ungraceful failure. The text also introduces the concept of **retroactive insufficiency**, where introducing new obligations mid‑operation can retroactively invalidate previously saved data, highlighting the importance of foresight and maintaining a look‑back margin of raw history.

This framework is not just about technical implementation but reflects deeper principles about constraint satisfaction, revealed versus declared priorities, and the inevitability of trade-offs when resources contract. It underscores that true resilience in systems—whether software or human institutions—depends on how well we can anticipate future changes and document our sacrifices to protect core purposes.
