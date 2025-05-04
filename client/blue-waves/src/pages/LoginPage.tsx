import { createSignal, useContext, Show, Signal } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { AuthContext } from "../index.tsx"; 

const LoginPage = () => {
    let email = "";
    let password = "";

    const [loginLoading, setLoginLoading] = createSignal(false);
    const [loginError, setLoginError] = createSignal("");

    const navigate = useNavigate();

    const [_, setToken] = useContext(AuthContext) as Signal<string>;

    const loginUser = async (event: Event) => {
        // Prevent refresh
        event.preventDefault();

        // Login user
        setLoginLoading(true);
        setLoginError("");

        const response = await fetch("http://localhost:8080/api/v1/users/login", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: `{"email":"${email}","password":"${password}"}`,
            credentials: "include"
        });

        if (response.ok) {
            setToken(await response.text());
            navigate("/home");
        } else {
            setLoginLoading(false);
            setLoginError(await response.text());
        }
    }

    return (
        <div class="flex justify-center items-center w-screen h-screen">
            <div class="flex flex-col items-center border-2 p-10" style="width: 40rem; height: 30rem;">
                <h1 class="text-2xl font-bold mb-4">Login</h1>
                <form onSubmit={loginUser} class="flex flex-col items-center">
                    <div class="flex flex-col m-4 text-xl">
                        <label for="email">Email</label>
                        <input id="email" type="email" class="border-2 w-96 h-10" onChange={(event) => {email = event.target.value; }} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="password">Password</label>
                        <input id="password" type="password" class="border-2 w-96 h-10" onChange={(event) => {password = event.target.value}} required/>
                    </div>
                    <button class="border-2 rounded px-10 py-2 mt-6 text-lg" disabled={loginLoading()}>Login</button>
                </form>
                <Show when={loginError() !== ""}>
                    <div class="flex justify-center items-center border-2 p-4 m-6 w-96 h-12">
                        <p>{loginError()}</p>
                    </div>
                </Show>
            </div>
        </div>
    )
}

export default LoginPage;
