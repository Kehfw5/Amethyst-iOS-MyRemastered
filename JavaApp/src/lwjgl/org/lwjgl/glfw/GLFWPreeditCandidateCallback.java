package org.lwjgl.glfw;

import org.lwjgl.system.*;
import javax.annotation.*;

/** Stub — iOS has no IME. */
public abstract class GLFWPreeditCandidateCallback extends Callback implements GLFWPreeditCandidateCallbackI {
    protected GLFWPreeditCandidateCallback() { super(CIF); }
    private static final long CIF = FunctionProviderI.callbackOf("(JJ)V");
    public static GLFWPreeditCandidateCallback create(long functionPointer) { return new Container(functionPointer, null); }
    private static final class Container extends GLFWPreeditCandidateCallback {
        Container(long functionPointer, Void __) { this.address = functionPointer; }
        public void invoke(long w, long c) { getCallable().invoke(w, c); }
    }
}
