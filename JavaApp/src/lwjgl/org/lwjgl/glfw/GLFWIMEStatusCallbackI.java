package org.lwjgl.glfw;

import org.lwjgl.system.*;
import javax.annotation.*;

/** Stub — iOS has no IME. */
@FunctionalInterface
public interface GLFWIMEStatusCallbackI extends CallbackI.V {
    void invoke(long window);
    @Override
    default String getSignature() { return "(J)V"; }
}
