import { query, redirect } from "@solidjs/router";
import { apiDomain } from "../index.tsx";

export const getToken = query(async () => {
    const response = await fetch(`${apiDomain}/api/v1/users/token`, {
        credentials: "include",
        referrerPolicy: "no-referrer"
    });

    if (response.ok) {
        return await response.text();
    } else {
        throw redirect("/login");
    }
}, "token");
