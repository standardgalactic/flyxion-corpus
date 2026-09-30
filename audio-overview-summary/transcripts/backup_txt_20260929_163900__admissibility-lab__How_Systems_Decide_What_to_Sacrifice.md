# backup_txt_20260929_163900/admissibility-lab/How_Systems_Decide_What_to_Sacrifice

The ARDO (Accountable Recoverable Degradation) framework is a rigorous, four-factor model designed to ensure that systems can degrade gracefully under overload without losing essential functionality or data. Each factor plays a critical role in maintaining the integrity and recoverability of the system:

1. **DO – Delegation Operator**: This component ensures there is a functional mechanism (like the Apollo uniform restart or safe pruning algorithms) capable of transitioning the system to an obligation-preserving state. Without a proper operator, even if other factors are met, the degradation process will fail.

2. **FO – Fixed Obligation Model**: The core invariant must be declared and fixed in advance, independent of any outcomes. This means that priorities cannot be self-adjusted based on what survives the crash; they must be predetermined to ensure meaningful recovery.

3. **HO – Historical Sufficiency**: Every task intended for future resumption must retain a representation (decontinuation tokens) that guarantees its continuation. Simply dumping raw payload bytes is insufficient because it doesn’t guarantee recoverability or relevance of data over time.

4. **WO – Witness Object**: Any excluded, suspended, or aborted tasks must receive an externally visible disposition witness. This prevents silent forgetting and ensures accountability for all system actions, even those that are temporarily halted.

These four factors interlock in such a way that the failure of any one leads to ungraceful degradation across the board. The ARDO framework is not just about surviving under pressure but ensuring that survival is meaningful and recoverable when conditions improve.

The concept of **retroactive insufficiency** highlights a critical vulnerability: if obligations change mid-emergency, data previously deemed unnecessary may become crucial for system recovery. This necessitates maintaining a **look-back margin**, where a rolling buffer of raw history is kept, even if it seems useless at the time, to safeguard against unforeseen future requirements.

This framework and its implications extend beyond technical systems into personal life, emphasizing that true priorities (revealed obligations) often differ from declared ones. The challenge lies in aligning our actions with our core values when resources contract, ensuring we are not just surviving but thriving under pressure.
