package org.lwjgl.glfw;

import org.lwjgl.system.*;
import javax.annotation.*;

/** Stub — iOS has no IME/preedit. */
@FunctionalInterface
public interface GLFWPreeditCallbackI extends CallbackI.V {
    void invoke(long window, int key, int scancode, int action, int mods, long preeditString);
    @Override
    default String getSignature() { return "(JIIIIJ)V"; }
}
