# backup_txt_20260929_171045/admissibility-lab/How_Systems_Decide_What_to_Sacrifice

The ARDO (Accountable Recoverable Degradation) framework is a rigorous, mathematical approach designed to ensure systems can gracefully degrade and recover from overload or failure without losing critical information or functionality. It consists of four interlocking factors that must all be present simultaneously for the system to operate correctly under stress:

1. **DO – Delegation Operator**: This factor ensures there is an effective mechanism in place—such as a safe pruning algorithm or a restart procedure like the Apollo uniform restart—to transition the system into an obligation-preserving state when degradation occurs.

2. **FO – Fixed Obligation Model**: The core invariant (the most important priority) must be declared and fixed before any operation begins, independent of what happens during execution. This prevents “self-sealing” where priorities are redefined after a crash based on whatever survives the failure.

3. **HO – Historical Sufficiency**: Every task that might need to be resumed later must retain sufficient representation (e.g., decontinuation tokens) to guarantee its future continuation, ensuring that critical state information is preserved and can be reconstructed if needed.

4. **WO – Witness Object**: Each excluded, suspended, or aborted task must receive an externally visible disposition witness. This prevents silent forgetting—ensuring that the system’s state changes are recorded and auditable.

The interlocking nature of these factors means that any failure in one area leads to a complete breakdown of the degradation process. For example:

- If only three factors (e.g., DO, FO, HO) are present but WO is missing, even if the operator works perfectly and history is saved, there’s no way to prove what was discarded or why, leading to potential loss of critical information.
  
- Conversely, having all four factors without a flawed operator might still result in failure if the system cannot adapt when external conditions change (e.g., new obligations are introduced), as discussed in the concept of retroactive insufficiency.

The framework also addresses dynamic environments where obligations can shift mid-operation. This is captured by the notion of **obligation set revision** and **retroactive insufficiency**, which highlights that a system optimized for current conditions may become insufficient if future obligations require information previously discarded due to resource constraints.

To mitigate such risks, the framework suggests maintaining a **look-back margin**, a buffer of raw data retained even when it seems useless at the time. This approach sacrifices present efficiency for future safety against unforeseen changes in requirements or rules—mirroring the analogy of packing an extra winter coat for a beach trip despite knowing you’ll likely not need it.

Ultimately, ARDO emphasizes that true system resilience lies not just in handling current overload but also in preparing for future unknowns by preserving both necessary information and potential alternatives. This holistic view aligns with broader philosophical questions about human institutions—how our declared priorities (intras) versus revealed actions (through sacrifices made under pressure) truly reflect our core values when resources are constrained.
