# admissibility-lab/How_Systems_Decide_What_to_Sacrifice

The ARDO (Accountable Recoverable Degradation) framework is built around four essential, interlocking factors that must all be present simultaneously for any degradation process—whether in software systems or human institutions—to succeed gracefully without ungraceful failure. Here’s a breakdown of each factor and how they interlock:

1. **DO – Delegation Operator**: This ensures the presence of a robust mechanism capable of transitioning the system to an obligation-preserving state, akin to mechanisms like the Apollo uniform restart or safe pruning algorithms that can mathematically guide the system through degradation without losing essential functionality.

2. **FO – Fixed Obligation Model**: The core invariant must be declared and fixed in advance, independent of any outcomes. This means you cannot adapt priorities based on what survives after a crash; instead, your goals remain constant regardless of external changes or failures.

3. **HO – Historical Sufficiency**: Every task planned to resume later must retain a representation that guarantees its future continuation—essentially decontinuation tokens rather than raw dump bytes. This ensures that the system can always recover and continue from where it left off without losing critical information.

4. **WO – Witness Object**: Each excluded, suspended, or aborted task must receive an adequate externally visible disposition witness. There is no silent forgetting; every state change is recorded to ensure accountability and traceability.

### Interlocking Nature

These four factors are interdependent:

- **DO + FO** create a stable foundation where the system knows exactly what it needs to preserve despite any degradation.
- **FO + HO** ensure that past states can be reconstructed, allowing for recovery even if resources contract or change unexpectedly.
- **HO + WO** guarantee that historical data is sufficient and visible, preventing loss of critical information during transitions.

If any one factor is missing or fails, the entire system’s ability to degrade gracefully collapses. For example:

- Without a proper DO (Delegation Operator), you might have flawless history but no mechanism to transition through degradation.
- Skipping FO (Fixed Obligation Model) means priorities can shift dynamically post-crash, leading to confusion about what was truly important.
- Missing HO (Historical Sufficiency) results in losing essential context for resuming tasks later.
- Neglecting WO (Witness Object) leads to silent forgetting of task states, making recovery impossible.

### Moving Target & Retroactive Insufficiency

The framework also addresses the dynamic nature of real-world systems through the concept of **obligation set revision** and **retroactive insufficiency**. This occurs when new obligations are introduced mid-emergency that rely on data previously deemed unnecessary to save resources. The analogy provided—packing for a beach vacation but being forced into Antarctica due to an unforeseen obligation—is powerful:

- It illustrates how perfectly optimized systems can become catastrophically flawed if they cannot anticipate future changes.
- The solution proposed is the **look-back margin**, which involves retaining a buffer of raw, unfiltered history. This sacrifices current efficiency for future safety against retroactive insufficiency.

### Broader Implications

The ARDO framework extends beyond technical applications into human institutions:

- It challenges individuals to consider whether their declared priorities (what they say) align with revealed obligations (what they actually choose when under pressure).
- The concept of **revealed obligations** highlights the gap between self-declared values and actual behavior during resource contraction.
- This introspection encourages a deeper understanding of personal and institutional resilience, emphasizing that true strength lies in maintaining core purposes despite overwhelming demands.

In summary, ARDO provides a rigorous mathematical framework for managing degradation across systems, ensuring stability through interlocking factors and addressing the inevitability of change with foresight and historical preservation.
