package org.lwjgl.glfw;

import org.lwjgl.system.*;
import javax.annotation.*;

/** Stub — iOS has no IME. */
@FunctionalInterface
public interface GLFWPreeditCandidateCallbackI extends CallbackI.V {
    void invoke(long window, long candidateList);
    @Override
    default String getSignature() { return "(JJ)V"; }
}
