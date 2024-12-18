import { createSignal, Show } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { createQuery } from "@tanstack/solid-query";
import { api } from "../index.tsx";

const LoginPage = () => {
    const [email, setEmail] = createSignal("");
    const [password, setPassword] = createSignal("");

    const navigate = useNavigate();

    const loginQuery = createQuery(() => ({
        queryKey: ["Login"],
        queryFn: async () => {
            // Login user
            await api.post("users/login", {
                json: {
                    email: email(),
                    password: password()
                },
                credentials: "include"
            });

            // Navigate to home page
            navigate("/home");

            return null;
        }
    }));

    const loginUser = async (event: Event) => {
        event.preventDefault();
        loginQuery.refetch();
    }

    return (
        <div class="flex justify-center items-center w-screen h-screen">
            <div class="flex flex-col items-center border-2 p-10" style="width: 40rem; height: 30rem;">
                <h1 class="text-2xl font-bold mb-4">Login</h1>
                <form onSubmit={loginUser} class="flex flex-col items-center">
                    <div class="flex flex-col m-4 text-xl">
                        <label for="email">Email</label>
                        <input id="email" type="email" class="border-2 w-96 h-10" onChange={(event) => setEmail(event.target.value)} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="password">Password</label>
                        <input id="password" type="password" class="border-2 w-96 h-10" onChange={(event) => setPassword(event.target.value)} required/>
                    </div>
                    <button class="border-2 rounded px-10 py-2 mt-6 text-lg" disabled={loginQuery.isFetching}>Login</button>
                </form>
                <Show when={loginQuery.isError}>
                    <div class="flex justify-center items-center border-2 p-4 m-6 w-96 h-12">
                        <p>{loginQuery.error!.message}</p>
                    </div>
                </Show>
            </div>
        </div>
    )
}

export default LoginPage;
