import { createContext, useContext } from 'react'

export const VolioContext = createContext(null)
export const useVolio = () => useContext(VolioContext)
