package org.lwjgl.glfw;

import org.lwjgl.system.*;
import javax.annotation.*;

/** Stub — iOS has no IME. */
public abstract class GLFWIMEStatusCallback extends Callback implements GLFWIMEStatusCallbackI {
    protected GLFWIMEStatusCallback() { super(CIF); }
    private static final long CIF = FunctionProviderI.callbackOf("(J)V");
    public static GLFWIMEStatusCallback create(long functionPointer) { return new Container(functionPointer, null); }
    private static final class Container extends GLFWIMEStatusCallback {
        Container(long functionPointer, Void __) { this.address = functionPointer; }
        public void invoke(long w) { getCallable().invoke(w); }
    }
}
