import { createSignal, Show } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { createQuery } from "@tanstack/solid-query";
import { api } from "../index.tsx";

const RegisterPage = () => {
    const [email, setEmail] = createSignal("");
    const [password, setPassword] = createSignal("");
    const [firstName, setFirstName] = createSignal("");
    const [lastName, setLastName] = createSignal("");

    const navigate = useNavigate();

    const registerQuery = createQuery(() => ({
        queryKey: ["Register"],
        queryFn: async () => {
            // Register user
            await api.post("users", {
                json: {
                    email: email(),
                    password: password(),
                    first_name: firstName(),
                    last_name: lastName()
                }
            });

            // Navigate to login page
            navigate("/login");

            return null;
        }
    }));

    const registerUser = (event: Event) => {
        event.preventDefault();
        registerQuery.refetch();
    }

    return (
        <div class="flex justify-center items-center w-screen h-screen">
            <div class="flex flex-col items-center border-2 p-10" style="width: 40rem; height: 42rem;">
                <h1 class="text-2xl font-bold mb-4">Register</h1>
                <form onSubmit={registerUser} class="flex flex-col items-center">
                    <div class="flex flex-col m-4 text-xl">
                        <label for="email">Email</label>
                        <input id="email" type="email" class="border-2 w-96 h-10" onChange={(event) => setEmail(event.target.value)} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="password">Password</label>
                        <input id="password" type="password" class="border-2 w-96 h-10" onChange={(event) => setPassword(event.target.value)} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="firstName">First Name</label>
                        <input id="firstName" class="border-2 w-96 h-10" onChange={(event) => setFirstName(event.target.value)} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="lastName">Last Name</label>
                        <input id="lastName" class="border-2 w-96 h-10" onChange={(event) => setLastName(event.target.value)} required/>
                    </div>
                    <button class="border-2 rounded p-2 mt-4 text-lg" disabled={registerQuery.isFetching}>Create Account</button>
                </form>
                <Show when={registerQuery.isError}>
                    <div class="flex justify-center items-center border-2 p-4 m-6 w-96 h-12">
                        <p>{registerQuery.error!.message}</p>
                    </div>
                </Show>
            </div>
        </div>
    )
}

export default RegisterPage;
