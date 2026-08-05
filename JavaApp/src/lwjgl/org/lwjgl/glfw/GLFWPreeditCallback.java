package org.lwjgl.glfw;

import org.lwjgl.system.*;
import javax.annotation.*;

/** Stub — iOS has no IME/preedit. */
public abstract class GLFWPreeditCallback extends Callback implements GLFWPreeditCallbackI {
    protected GLFWPreeditCallback() { super(CIF); }
    private static final long CIF = FunctionProviderI.callbackOf("(JIIIIJ)V");
    public static GLFWPreeditCallback create(long functionPointer) { return new Container(functionPointer, null); }
    private static final class Container extends GLFWPreeditCallback {
        Container(long functionPointer, Void __) { this.address = functionPointer; }
        public void invoke(long w, int k, int s, int a, int m, long p) { getCallable().invoke(w, k, s, a, m, p); }
    }
}
