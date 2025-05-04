import { createSignal, Show } from "solid-js";
import { useNavigate } from "@solidjs/router";

const RegisterPage = () => {
    let email = "";
    let password = "";
    let firstName = "";
    let lastName = "";

    const [registerLoading, setRegisterLoading] = createSignal(false);
    const [registerError, setRegisterError] = createSignal("");

    const navigate = useNavigate();

    const registerUser = async (event: Event) => {
        // Prevent default refresh
        event.preventDefault();

        // Register user
        setRegisterLoading(true);
        setRegisterError("");

        const response = await fetch("http://localhost:8080/api/v1/users", {
            method: "POST",
            headers: { "Content-Type": "text/plain" },
            body: `${email}\n${password}\n${firstName}\n${lastName}`
        });

        if (response.ok) navigate("/login");

        setRegisterLoading(false);
        setRegisterError(await response.text());
    }

    return (
        <div class="flex justify-center items-center w-screen h-screen">
            <div class="flex flex-col items-center border-2 p-10" style="width: 40rem; height: 42rem;">
                <h1 class="text-2xl font-bold mb-4">Register</h1>
                <form onSubmit={registerUser} class="flex flex-col items-center">
                    <div class="flex flex-col m-4 text-xl">
                        <label for="email">Email</label>
                        <input id="email" type="email" class="border-2 w-96 h-10" onChange={(event) => {email = event.target.value}} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="password">Password</label>
                        <input id="password" type="password" class="border-2 w-96 h-10" onChange={(event) => {password = event.target.value}} minlength={8} maxLength={71} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="firstName">First Name</label>
                        <input id="firstName" class="border-2 w-96 h-10" onChange={(event) => {firstName = event.target.value}} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="lastName">Last Name</label>
                        <input id="lastName" class="border-2 w-96 h-10" onChange={(event) => {lastName = event.target.value}} required/>
                    </div>
                    <button class="border-2 rounded p-2 mt-4 text-lg" disabled={registerLoading()}>Create Account</button>
                </form>
                <Show when={registerError() !== ""}>
                    <div class="flex justify-center items-center border-2 p-4 m-6 w-96 h-12">
                        <p>{registerError()}</p>
                    </div>
                </Show>
            </div>
        </div>
    )
}

export default RegisterPage;
